import Foundation
import PrivateKeyboardCore
import PrivateKeyboardUpdater
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: KeyboardSettings
    @Published private(set) var userWordCount = 0
    @Published private(set) var customWords: [UserLexiconEntry] = []
    @Published private(set) var datasetVersion = "—"
    @Published private(set) var datasetSource = "—"
    @Published private(set) var modelStatus = "未加载"
    @Published private(set) var updateStatus = "尚未检查"
    @Published private(set) var isBusy = false
    @Published private(set) var isUpdateConfigured = false

    private let settingsStore: SharedSettingsStore
    private let userHistory: UserHistoryStore
    private let userLexicon: UserLexiconStore
    private let installer: DatasetInstaller
    private let updateService: UpdateService
    private var didRunStartup = false

    init() {
        let container = AppGroup.containerURL() ?? {
            let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PrivateKeyboardFallback", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }()
        let settingsStore = SharedSettingsStore(defaults: AppGroup.settingsDefaults())
        let userHistory = UserHistoryStore(containerURL: container)
        let userLexicon = UserLexiconStore(containerURL: container)
        let installer = DatasetInstaller(containerURL: container)
        let configuration = UpdateConfiguration.load()
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.userHistory = userHistory
        self.userLexicon = userLexicon
        self.installer = installer
        let session = URLSession(configuration: .ephemeral)
        self.updateService = UpdateService(installer: installer, configuration: configuration, session: session)
        self.isUpdateConfigured = configuration.isConfigured
        self.userWordCount = userHistory.trackedWordCount
        self.customWords = userLexicon.allEntries
        refreshDatasetInfo()
        if !isUpdateConfigured {
            updateStatus = "未配置更新源（见 README）"
        }
    }

    func performStartupTasks() async {
        guard !didRunStartup else { return }
        didRunStartup = true
        guard isUpdateConfigured else { return }
        await checkAndInstallIfNeeded(automatic: true)
    }

    func setSound(_ enabled: Bool) {
        settings.soundEnabled = enabled
        save()
    }

    func setHaptics(_ enabled: Bool) {
        settings.hapticsEnabled = enabled
        save()
    }

    func setFuzzy(_ keyPath: WritableKeyPath<FuzzyPinyinOptions, Bool>, value: Bool) {
        settings.fuzzy[keyPath: keyPath] = value
        save()
    }

    func setScript(_ script: ScriptPreference) {
        settings.script = script
        save()
    }

    func checkForUpdates() {
        Task { await checkAndInstallIfNeeded(automatic: false) }
    }

    func clearPersonalData() {
        userHistory.clear()
        userLexicon.clear()
        customWords = []
        userWordCount = 0
        updateStatus = "已清除本地词频、最近使用记录和自定义词库"
    }

    func addCustomWord(word: String, pinyin: String, note: String) -> String? {
        do {
            _ = try userLexicon.add(word: word, pinyin: pinyin, note: note)
            customWords = userLexicon.allEntries
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeCustomWord(id: UUID) {
        userLexicon.remove(id: id)
        customWords = userLexicon.allEntries
    }

    func reloadCustomWords() {
        userLexicon.reload()
        customWords = userLexicon.allEntries
    }

    func rollbackDataset() {
        isBusy = true
        defer { isBusy = false }
        do {
            try installer.rollback()
            updateStatus = "已回滚到上一个本地数据版本"
            refreshDatasetInfo()
        } catch {
            updateStatus = "回滚失败：\(error.localizedDescription)"
        }
    }

    func refreshDatasetInfo() {
        if let resolved = DatasetResolver.resolve(containerURL: AppGroup.containerURL()) {
            datasetVersion = resolved.version
            datasetSource = resolved.source == .appGroup ? "App Group（已更新）" : "键盘扩展内置"
        } else {
            datasetVersion = bundledDataVersion
            datasetSource = "键盘扩展内置"
        }
        // Intentionally do not load the 30 MB dictionary or Core ML model in the
        // host app. The keyboard extension owns inference memory; the host app
        // only manages settings and signed data updates.
        if let state = installer.currentState().current, !state.modelVersion.isEmpty {
            modelStatus = "Core ML \(state.modelVersion)（App Group）"
        } else {
            modelStatus = "Core ML \(bundledModelVersion)（扩展内置）"
        }
        userWordCount = userHistory.trackedWordCount
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func save() {
        settingsStore.save(settings)
    }

    private func checkAndInstallIfNeeded(automatic: Bool) async {
        guard isUpdateConfigured else {
            updateStatus = "未配置更新源（见 README）"
            return
        }
        isBusy = true
        updateStatus = automatic ? "启动检查更新…" : "检查更新…"
        defer { isBusy = false }
        do {
            let currentVersion = currentDatasetVersion
            guard let result = try await updateService.checkForUpdate(currentVersion: currentVersion) else {
                updateStatus = "没有可用的新版本"
                return
            }
            guard result.isNewer else {
                updateStatus = "已是最新版本 \(currentVersion)"
                return
            }
            updateStatus = "发现 \(result.manifest.dataVersion)，校验并安装…"
            _ = try await updateService.install(result.manifest, appVersion: appVersion)
            updateStatus = "已安装 \(result.manifest.dataVersion)"
            refreshDatasetInfo()
        } catch {
            updateStatus = "更新失败，继续使用旧版本：\(error.localizedDescription)"
        }
    }

    private var currentDatasetVersion: String {
        DatasetResolver.resolve(containerURL: AppGroup.containerURL())?.version ?? bundledDataVersion
    }

    private var bundledDataVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "PBDataVersion") as? String) ?? "0"
    }

    private var bundledModelVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "PBModelVersion") as? String) ?? "unknown"
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }
}
