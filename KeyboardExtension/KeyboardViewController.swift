import PrivateKeyboardCore
import UIKit

final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController {
    private let keyboardView = KeyboardView()
    private let predictionQueue = DispatchQueue(label: "com.privatekeyboard.prediction", qos: .userInteractive)
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private lazy var containerURL: URL = {
        if let url = AppGroup.containerURL() { return url }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateKeyboardKeyboardFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()
    private lazy var settingsStore = SharedSettingsStore(defaults: AppGroup.settingsDefaults())
    private lazy var userHistory = UserHistoryStore(containerURL: containerURL)

    private var settings = KeyboardSettings()
    private var engine: PredictionEngine?
    private var activeDatasetVersion: String?
    private var isLoadingEngine = false
    private var predictionGeneration = 0
    private var candidates: [InputCandidate] = []
    private var pinyinBuffer = ""
    private var englishBuffer = ""
    private var contextWords: [String] = []
    private var language: InputLanguage = .chinese
    private var page: KeyboardPage = .letters
    private var isShifted = false

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

    override func viewDidLoad() {
        super.viewDidLoad()
        haptic.prepare()
        settings = settingsStore.load()
        language = settings.lastLanguage
        isShifted = language == .english
        keyboardView.configure(page: page, language: language, shifted: isShifted, force: true)
        loadEngineIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = settingsStore.load()
        userHistory.reload()
        if settings.lastLanguage != language {
            language = settings.lastLanguage
            keyboardView.configure(page: page, language: language, shifted: isShifted, force: true)
        }
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
        let settingsSnapshot = settings
        predictionQueue.async { [weak self] in
            var loaded = try? PredictionEngine(
                paths: paths,
                userHistory: history,
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
        switch action {
        case .character(let value):
            handleCharacter(value)
        case .backspace:
            handleBackspace()
        case .shift:
            isShifted.toggle()
            keyboardView.configure(page: page, language: language, shifted: isShifted)
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
            keyboardView.configure(page: page, language: language, shifted: isShifted)
        case .emoji(let emoji):
            commitFirstCandidateIfAny()
            englishBuffer = ""
            textDocumentProxy.insertText(emoji)
            autoShiftIfNeeded()
            refreshCandidates()
        }
    }

    private func handleCharacter(_ rawValue: String) {
        guard !rawValue.isEmpty else { return }
        let isLetter = rawValue.count == 1 && rawValue.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) && $0.isASCII
        }

        if page == .letters, isLetter {
            if language == .chinese {
                guard pinyinBuffer.count < 40 else { return }
                let lower = rawValue.lowercased()
                pinyinBuffer.append(lower)
                textDocumentProxy.insertText(lower)
                refreshCandidates()
                return
            } else {
                guard englishBuffer.count < 48 else { return }
                let value = isShifted ? rawValue.uppercased() : rawValue.lowercased()
                englishBuffer.append(Character(value))
                textDocumentProxy.insertText(value)
                isShifted = false
                keyboardView.configure(page: page, language: language, shifted: isShifted)
                refreshCandidates()
                return
            }
        }

        commitFirstCandidateIfAny()
        englishBuffer = ""
        let text = language == .chinese ? smartPunctuation(rawValue) : rawValue
        textDocumentProxy.insertText(text)
        autoShiftIfNeeded()
        refreshCandidates()
    }

    private func handleBackspace() {
        if language == .chinese, !pinyinBuffer.isEmpty {
            pinyinBuffer.removeLast()
            textDocumentProxy.deleteBackward()
        } else if language == .english, !englishBuffer.isEmpty {
            englishBuffer.removeLast()
            textDocumentProxy.deleteBackward()
        } else {
            textDocumentProxy.deleteBackward()
        }
        refreshCandidates()
    }

    private func handleSpace() {
        if language == .chinese, !pinyinBuffer.isEmpty {
            if commitFirstCandidateIfAny() {
                return
            }
            pinyinBuffer = ""
            textDocumentProxy.insertText(" ")
        } else {
            if language == .english {
                englishBuffer = ""
                isShifted = true
            }
            textDocumentProxy.insertText(" ")
        }
        autoShiftIfNeeded()
        refreshCandidates()
        keyboardView.configure(page: page, language: language, shifted: isShifted)
    }

    private func handleReturn() {
        if language == .chinese, !pinyinBuffer.isEmpty {
            _ = commitFirstCandidateIfAny()
        }
        englishBuffer = ""
        textDocumentProxy.insertText("\n")
        autoShiftIfNeeded()
        refreshCandidates()
    }

    private func toggleLanguage() {
        if language == .chinese, !pinyinBuffer.isEmpty {
            if !commitFirstCandidateIfAny() {
                deletePinyinBuffer()
            }
        }
        englishBuffer = ""
        language = language == .chinese ? .english : .chinese
        page = .letters
        isShifted = language == .english
        settings.lastLanguage = language
        settingsStore.save(settings)
        keyboardView.configure(page: page, language: language, shifted: isShifted, force: true)
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
            keyboardView.configure(page: page, language: language, shifted: isShifted)
            return
        }
        isShifted = true
        keyboardView.configure(page: page, language: language, shifted: isShifted)
    }

    private func deletePinyinBuffer() {
        let count = pinyinBuffer.utf16.count
        guard count > 0 else { return }
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        pinyinBuffer = ""
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
        let deletionCount: Int
        if language == .chinese {
            deletionCount = pinyinBuffer.utf16.count
            pinyinBuffer = ""
        } else {
            deletionCount = englishBuffer.utf16.count
            englishBuffer = ""
        }
        if candidate.kind != .raw {
            for _ in 0..<deletionCount { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(candidate.text)
            userHistory.recordSelection(of: candidate.text)
            if candidate.kind == .chinese || candidate.kind == .composed {
                contextWords.append(candidate.text)
                if contextWords.count > 3 {
                    contextWords.removeFirst(contextWords.count - 3)
                }
            }
        }
        isShifted = language == .english ? true : false
        candidates = []
        keyboardView.update(candidates: [])
        keyboardView.configure(page: page, language: language, shifted: isShifted)
        refreshCandidates()
    }

    private func refreshCandidates() {
        let query = language == .chinese ? pinyinBuffer : englishBuffer
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
            let result = (try? engine.predict(
                input: query,
                language: currentLanguage,
                contextWords: context,
                fuzzy: fuzzy,
                scriptPreference: scriptPreference,
                limit: 40
            )) ?? []
            DispatchQueue.main.async {
                guard let self, generation == self.predictionGeneration else { return }
                self.candidates = result
                self.keyboardView.update(candidates: result)
            }
        }
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
