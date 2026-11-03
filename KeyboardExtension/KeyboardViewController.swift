import PrivateKeyboardCore
import UIKit

protocol KeyboardTextSink: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
}

private final class TextDocumentProxySink: KeyboardTextSink {
    private let proxy: UITextDocumentProxy
    init(proxy: UITextDocumentProxy) { self.proxy = proxy }
    func insertText(_ text: String) { proxy.insertText(text) }
    func deleteBackward() { proxy.deleteBackward() }
}

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private let keyboardView = KeyboardView()
    private let predictionQueue = DispatchQueue(label: "com.privatekeyboard.prediction", qos: .userInteractive)
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    /// Test seam: production uses the document proxy; Catalyst input smoke uses
    /// a recording sink.
    var textSinkOverride: KeyboardTextSink?

    private var textSink: KeyboardTextSink {
        textSinkOverride ?? TextDocumentProxySink(proxy: textDocumentProxy)
    }

    private lazy var containerURL: URL = {
        if let url = AppGroup.containerURL() { return url }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateKeyboardKeyboardFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()
    private lazy var settingsStore = SharedSettingsStore(defaults: AppGroup.settingsDefaults())
    private lazy var userHistory = UserHistoryStore(containerURL: containerURL)
    private lazy var userLexicon = UserLexiconStore(containerURL: containerURL)

    private var settings = KeyboardSettings()
    private var engine: PredictionEngine?
    private var activeDatasetVersion: String?
    private var isLoadingEngine = false
    private var predictionGeneration = 0
    private var candidates: [InputCandidate] = []
    private var pinyinBuffer = ""
    private var t9Buffer = ""
    private var englishBuffer = ""
    private var contextWords: [String] = []
    private var language: InputLanguage = .chinese
    private var nineKeyEnabled = false
    private var page: KeyboardPage = .letters
    private var isShifted = false
    private var shiftLocked = false
    private var lastShiftTap: TimeInterval = 0
    private var returnKeyLabel = "换行"
    private var compositionMonitor: Timer?

    override func loadView() {
        let root = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        root.allowsSelfSizing = true
        root.backgroundColor = KeyboardTheme.background
        view = root

        keyboardView.onAction = { [weak self] action in
            self?.handle(action)
        }
        keyboardView.onSelectCandidate = { [weak self] candidate in
            self?.feedback()
            self?.commit(candidate: candidate)
        }
        keyboardView.onFeedback = { [weak self] in
            self?.feedback()
        }
        keyboardView.onCursorMove = { [weak self] offset in
            self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        }
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardTheme.keyboardHeight)
        height.priority = UILayoutPriority(999)
        height.isActive = true
        preferredContentSize = CGSize(width: 0, height: KeyboardTheme.keyboardHeight)
    }

    deinit {
        compositionMonitor?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        haptic.prepare()
        settings = settingsStore.load()
        language = settings.lastLanguage
        nineKeyEnabled = settings.nineKeyEnabled
        isShifted = language == .english
        updateReturnKeyLabel()
        refreshKeyboard(force: true)
        loadEngineIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = settingsStore.load()
        userHistory.reload()
        userLexicon.reload()
        let previousNineKey = nineKeyEnabled
        nineKeyEnabled = settings.nineKeyEnabled
        if settings.lastLanguage != language {
            language = settings.lastLanguage
            shiftLocked = false
            isShifted = language == .english
        }
        if previousNineKey != nineKeyEnabled {
            page = .letters
            refreshKeyboard(force: true)
        }
        updateReturnKeyLabel()
        refreshKeyboard(force: true)
        if let resolved = DatasetResolver.resolve(containerURL: AppGroup.containerURL()),
           resolved.version != activeDatasetVersion {
            loadEngineIfNeeded(force: true)
        }
    }

    private func loadEngineIfNeeded(force: Bool = false) {
        guard (engine == nil || force), !isLoadingEngine else { return }
        isLoadingEngine = true
        let container = AppGroup.containerURL()
        let resolved = DatasetResolver.resolve(containerURL: container)
        guard let resolved else {
            isLoadingEngine = false
            return
        }
        let paths = resolved.paths
        let fallback: (paths: DatasetPaths, version: String)?
        if resolved.source == .appGroup {
            fallback = DatasetResolver.resolve(containerURL: nil).map { ($0.paths, $0.version) }
        } else {
            fallback = nil
        }
        let history = userHistory
        let lexicon = userLexicon
        let settingsSnapshot = settings
        predictionQueue.async { [weak self] in
            var loaded = try? PredictionEngine(
                paths: paths,
                userHistory: history,
                userLexicon: lexicon,
                fuzzyOptions: settingsSnapshot.fuzzy
            )
            var loadedVersion = resolved.version
            if loaded == nil, let fallback,
               let fallbackEngine = try? PredictionEngine(
                   paths: fallback.paths,
                   userHistory: history,
                   fuzzyOptions: settingsSnapshot.fuzzy
               ) {
                loaded = fallbackEngine
                loadedVersion = fallback.version
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let loaded {
                    self.engine = loaded
                    self.activeDatasetVersion = loadedVersion
                }
                self.isLoadingEngine = false
                if loaded != nil {
                    self.refreshCandidates()
                }
            }
        }
    }

    private func handle(_ action: KeyAction) {
        updateReturnKeyLabel()
        reconcileCompositionWithDocument()
        switch action {
        case .character(let value):
            handleCharacter(value)
        case .backspace:
            handleBackspace()
        case .shift:
            guard language == .english else { return }
            let now = Date().timeIntervalSinceReferenceDate
            if now - lastShiftTap < 0.35 {
                shiftLocked.toggle()
                isShifted = shiftLocked
            } else {
                isShifted.toggle()
                if !isShifted { shiftLocked = false }
            }
            lastShiftTap = now
            refreshKeyboard()
        case .space:
            handleSpace()
        case .returnKey:
            handleReturn()
        case .nextKeyboard:
            advanceToNextInputMode()
        case .toggleLanguage:
            toggleLanguage()
        case .page(let nextPage):
            page = nextPage
            refreshKeyboard(force: true)
        }
    }

    private func handleCharacter(_ rawValue: String) {
        guard !rawValue.isEmpty else { return }
        let isLetter = rawValue.count == 1 && rawValue.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) && $0.isASCII
        }

        if page == .letters, language == .chinese, nineKeyEnabled,
           rawValue.count == 1, "23456789".contains(rawValue) {
            guard t9Buffer.count < 24 else { return }
            t9Buffer.append(rawValue)
            textSink.insertText(rawValue)
            startCompositionMonitor()
            refreshCandidates()
            return
        }

        if page == .letters, isLetter, !(language == .chinese && nineKeyEnabled) {
            if language == .chinese {
                guard pinyinBuffer.count < 40 else { return }
                let lower = rawValue.lowercased()
                pinyinBuffer.append(lower)
                textSink.insertText(lower)
                startCompositionMonitor()
                refreshCandidates()
                return
            } else {
                guard englishBuffer.count < 48 else { return }
                let value = isShifted ? rawValue.uppercased() : rawValue.lowercased()
                englishBuffer.append(Character(value))
                textSink.insertText(value)
                isShifted = shiftLocked
                refreshKeyboard()
                startCompositionMonitor()
                refreshCandidates()
                return
            }
        }

        commitFirstCandidateIfAny()
        if language == .chinese, nineKeyEnabled {
            t9Buffer = ""
        }
        englishBuffer = ""
        let text = language == .chinese ? smartPunctuation(rawValue) : rawValue
        textSink.insertText(text)
        autoShiftIfNeeded()
        refreshCandidates()
    }

    private func handleBackspace() {
        if language == .chinese, nineKeyEnabled, !t9Buffer.isEmpty {
            t9Buffer.removeLast()
            textSink.deleteBackward()
        } else if language == .chinese, !pinyinBuffer.isEmpty {
            pinyinBuffer.removeLast()
            textSink.deleteBackward()
        } else if language == .english, !englishBuffer.isEmpty {
            englishBuffer.removeLast()
            textSink.deleteBackward()
        } else {
            textSink.deleteBackward()
        }
        if pinyinBuffer.isEmpty && t9Buffer.isEmpty && englishBuffer.isEmpty {
            stopCompositionMonitor()
        }
        refreshCandidates()
    }

    private func handleSpace() {
        if language == .chinese, nineKeyEnabled, !t9Buffer.isEmpty {
            if commitFirstCandidateIfAny() { return }
            t9Buffer = ""
            textSink.insertText(" ")
        } else if language == .chinese, !pinyinBuffer.isEmpty {
            if commitFirstCandidateIfAny() {
                return
            }
            pinyinBuffer = ""
            textSink.insertText(" ")
        } else {
            if language == .english {
                englishBuffer = ""
                isShifted = true
            }
            textSink.insertText(" ")
        }
        autoShiftIfNeeded()
        refreshCandidates()
        refreshKeyboard()
    }

    private func handleReturn() {
        if language == .chinese, nineKeyEnabled, !t9Buffer.isEmpty {
            let raw = t9Buffer
            deleteCompositionBuffer()
            textSink.insertText(raw)
        } else if language == .chinese, !pinyinBuffer.isEmpty {
            let raw = pinyinBuffer
            deleteCompositionBuffer()
            textSink.insertText(raw)
        }
        englishBuffer = ""
        textSink.insertText("\n")
        autoShiftIfNeeded()
        refreshCandidates()
    }

    private func toggleLanguage() {
        if language == .chinese, (nineKeyEnabled ? !t9Buffer.isEmpty : !pinyinBuffer.isEmpty) {
            if !commitFirstCandidateIfAny() {
                deleteCompositionBuffer()
            }
        }
        englishBuffer = ""
        language = language == .chinese ? .english : .chinese
        page = .letters
        t9Buffer = ""
        shiftLocked = false
        isShifted = language == .english
        settings.lastLanguage = language
        settingsStore.save(settings)
        refreshKeyboard(force: true)
        refreshCandidates()
    }

    private func smartPunctuation(_ value: String) -> String {
        guard language == .chinese else { return value }
        switch value {
        case ".": return "。"
        case ",": return "，"
        case "?": return "？"
        case "!": return "！"
        case ":": return "："
        case ";": return "；"
        case "(": return "（"
        case ")": return "）"
        default: return value
        }
    }

    private func autoShiftIfNeeded() {
        guard language == .english else {
            isShifted = false
            refreshKeyboard()
            return
        }
        isShifted = true
        refreshKeyboard()
    }

    private var activeBufferCount: Int {
        if language == .english { return englishBuffer.utf16.count }
        if nineKeyEnabled, !t9Buffer.isEmpty { return t9Buffer.utf16.count }
        return pinyinBuffer.utf16.count
    }

    private func deleteCompositionBuffer() {
        let count = activeBufferCount
        guard count > 0 else { return }
        for _ in 0..<count { textSink.deleteBackward() }
        pinyinBuffer = ""
        t9Buffer = ""
        englishBuffer = ""
        stopCompositionMonitor()
    }

    @discardableResult
    private func commitFirstCandidateIfAny() -> Bool {
        guard let first = candidates.first else { return false }
        if first.kind == .raw {
            pinyinBuffer = ""
            englishBuffer = ""
            return false
        }
        commit(candidate: first)
        return true
    }

    private func commit(candidate: InputCandidate) {
        let deletionCount = activeBufferCount
        pinyinBuffer = ""
        t9Buffer = ""
        englishBuffer = ""
        if candidate.kind != .raw {
            for _ in 0..<deletionCount { textSink.deleteBackward() }
            textSink.insertText(candidate.text)
            userHistory.recordSelection(of: candidate.text)
            if candidate.kind == .chinese || candidate.kind == .composed || candidate.kind == .custom {
                contextWords.append(candidate.text)
                if contextWords.count > 3 {
                    contextWords.removeFirst(contextWords.count - 3)
                }
            }
        }
        isShifted = language == .english
        candidates = []
        keyboardView.update(candidates: [])
        refreshKeyboard()
        refreshCandidates()
    }

    private func refreshCandidates() {
        let isT9 = language == .chinese && nineKeyEnabled && !t9Buffer.isEmpty
        let query = isT9 ? t9Buffer : (language == .chinese ? pinyinBuffer : englishBuffer)
        guard !query.isEmpty, let engine else {
            predictionGeneration += 1
            candidates = []
            keyboardView.update(candidates: [])
            return
        }
        predictionGeneration += 1
        let generation = predictionGeneration
        let context = contextWords
        let currentLanguage = language
        let fuzzy = settings.fuzzy
        let scriptPreference = settings.script
        predictionQueue.async { [weak self] in
            let result: [InputCandidate]
            if isT9 {
                result = (try? engine.predictT9(
                    digits: query,
                    contextWords: context,
                    fuzzy: fuzzy,
                    scriptPreference: scriptPreference,
                    limit: 40
                )) ?? []
            } else {
                result = (try? engine.predict(
                    input: query,
                    language: currentLanguage,
                    contextWords: context,
                    fuzzy: fuzzy,
                    scriptPreference: scriptPreference,
                    limit: 40
                )) ?? []
            }
            DispatchQueue.main.async {
                guard let self, generation == self.predictionGeneration else { return }
                self.candidates = result
                self.keyboardView.update(candidates: result)
            }
        }
    }

    private func refreshKeyboard(force: Bool = false) {
        keyboardView.configure(
            page: page,
            language: language,
            shifted: isShifted,
            capsLocked: shiftLocked,
            returnKeyLabel: returnKeyLabel,
            nineKey: nineKeyEnabled,
            force: force
        )
    }

    private func updateReturnKeyLabel() {
        let type = textDocumentProxy.returnKeyType
        let label: String
        switch type {
        case .go: label = "前往"
        case .google, .search, .yahoo: label = "搜索"
        case .join: label = "加入"
        case .next: label = "下一项"
        case .route: label = "路线"
        case .send: label = "发送"
        case .done: label = "完成"
        case .emergencyCall: label = "紧急呼叫"
        case .continue: label = "继续"
        default: label = "换行"
        }
        if label != returnKeyLabel {
            returnKeyLabel = label
            refreshKeyboard()
        }
    }

    private func reconcileCompositionWithDocument() {
        guard textSinkOverride == nil else { return }
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        if language == .chinese, nineKeyEnabled, !t9Buffer.isEmpty, !context.hasSuffix(t9Buffer) {
            t9Buffer = ""
            predictionGeneration += 1
            candidates = []
            keyboardView.update(candidates: [])
            stopCompositionMonitor()
        } else if language == .chinese, !pinyinBuffer.isEmpty, !context.hasSuffix(pinyinBuffer) {
            pinyinBuffer = ""
            predictionGeneration += 1
            candidates = []
            keyboardView.update(candidates: [])
            stopCompositionMonitor()
        } else if language == .english, !englishBuffer.isEmpty, !context.hasSuffix(englishBuffer) {
            englishBuffer = ""
            predictionGeneration += 1
            candidates = []
            keyboardView.update(candidates: [])
            stopCompositionMonitor()
        }
    }

    private func startCompositionMonitor() {
        guard textSinkOverride == nil, compositionMonitor == nil else { return }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.reconcileCompositionWithDocument()
        }
        RunLoop.main.add(timer, forMode: .common)
        compositionMonitor = timer
    }

    private func stopCompositionMonitor() {
        compositionMonitor?.invalidate()
        compositionMonitor = nil
    }

    private func feedback() {
        if settings.soundEnabled {
            UIDevice.current.playInputClick()
        }
        if settings.hapticsEnabled {
            haptic.impactOccurred(intensity: 0.55)
            haptic.prepare()
        }
    }
}
