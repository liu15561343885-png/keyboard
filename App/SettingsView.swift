import PrivateKeyboardCore
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = AppModel()
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("完全离线，本地候选", systemImage: "lock.shield")
                        .font(.headline)
                    Text("拼音、词库、语言模型、Core ML 排序和个人词频均在本机处理。键盘扩展没有网络代码。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("启用键盘") {
                    Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → PrivateKeyboard。无需“允许完全访问”。")
                        .font(.callout)
                    Button("打开系统设置") { model.openSystemSettings() }
                }

                Section("输入设置") {
                    Toggle("按键音", isOn: Binding(
                        get: { model.settings.soundEnabled },
                        set: { model.setSound($0) }
                    ))
                    Toggle("触感反馈", isOn: Binding(
                        get: { model.settings.hapticsEnabled },
                        set: { model.setHaptics($0) }
                    ))
                    Picker("字形", selection: Binding(
                        get: { model.settings.script },
                        set: { model.setScript($0) }
                    )) {
                        ForEach(ScriptPreference.allCases, id: \.self) { script in
                            Text(script.displayName).tag(script)
                        }
                    }
                    .pickerStyle(.segmented)
                    NavigationLink("自定义词库") { CustomWordsView(model: model) }
                }

                Section {
                    fuzzyToggle("z / zh 模糊音", keyPath: \.zhZ)
                    fuzzyToggle("c / ch 模糊音", keyPath: \.chC)
                    fuzzyToggle("s / sh 模糊音", keyPath: \.shS)
                    fuzzyToggle("n / l 模糊音", keyPath: \.nL)
                    fuzzyToggle("f / h 模糊音", keyPath: \.fH)
                    fuzzyToggle("ang / an", keyPath: \.angAn)
                    fuzzyToggle("eng / en", keyPath: \.engEn)
                    fuzzyToggle("ing / in", keyPath: \.ingIn)
                } header: {
                    Text("模糊拼音")
                } footer: {
                    Text("设置会写入 App Group，键盘扩展下次显示时生效。")
                }

                Section("本地数据") {
                    LabeledContent("词库版本", value: model.datasetVersion)
                    LabeledContent("数据来源", value: model.datasetSource)
                    LabeledContent("排序模型", value: model.modelStatus)
                    LabeledContent("个人词条", value: "\(model.userWordCount)")
                    Button {
                        model.checkForUpdates()
                    } label: {
                        HStack {
                            Text("检查词库更新")
                            Spacer()
                            if model.isBusy { ProgressView() }
                        }
                    }
                    .disabled(model.isBusy)
                    Button("回滚到上一版本") { model.rollbackDataset() }
                        .disabled(model.isBusy)
                    Text(model.updateStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink("隐私说明") { PrivacyView() }
                    NavigationLink("开源许可与数据来源") { LicensesView() }
                    LabeledContent("版本", value: appVersion)
                } header: {
                    Text("关于")
                }

                Section {
                    Button("清除个人词库与词频", role: .destructive) {
                        showClearConfirmation = true
                    }
                } footer: {
                    Text("只会删除本机 App Group 中的用户词频、最近使用记录和自定义词库，不会影响共享词库。")
                }
            }
            .navigationTitle("PrivateKeyboard")
            .task { await model.performStartupTasks() }
            .alert("清除个人数据？", isPresented: $showClearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) { model.clearPersonalData() }
            } message: {
                Text("此操作不可撤销，且不会上传任何数据。")
            }
        }
    }

    private func fuzzyToggle(
        _ title: String,
        keyPath: WritableKeyPath<FuzzyPinyinOptions, Bool>
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { model.settings.fuzzy[keyPath: keyPath] },
            set: { model.setFuzzy(keyPath, value: $0) }
        ))
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }
}

private struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("PrivateKeyboard Core").font(.headline)
                Text("Apache License 2.0。完整文本见仓库 LICENSE。")
                Divider()
                Text("CC-CEDICT").font(.headline)
                Text("开发种子数据包含由 CC-CEDICT 派生的字段。CC-CEDICT 由 MDBG 发布，采用 CC BY-SA 4.0。发布用词库由 GitHub Actions 重新构建，并随 release 附上来源、版本、修改说明、许可证和署名。")
                Divider()
                Text("jieba 词频（可选构建输入）").font(.headline)
                Text("如构建流程使用其词频数据，将遵循其 MIT 许可证并在发布物中署名。")
                Divider()
                Text("不包含第三方输入法的私有词库、接口或代码。")
            }
            .padding()
        }
        .navigationTitle("许可与来源")
    }
}
