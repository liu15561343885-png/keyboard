import PrivateKeyboardCore
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = AppModel()
    @State private var showClearConfirmation = false
    @State private var testText = ""
    @FocusState private var testFocused: Bool

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

                Section("键盘测试") {
                    TextField("点击这里试用 PrivateKeyboard", text: $testText, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($testFocused)
                        .accessibilityIdentifier("keyboardTestField")
                    Text("启用键盘后点此输入；数据只在本机处理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("启用键盘") {
                    Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → PrivateKeyboard。随后打开“允许完全访问”，用于读取 App Group 中的词库、设置和用户词频。")
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
                    Picker("中文键盘布局", selection: Binding(
                        get: { model.settings.nineKeyEnabled },
                        set: { model.setNineKey($0) }
                    )) {
                        Text("26 键").tag(false)
                        Text("九键").tag(true)
                    }
                    .pickerStyle(.segmented)
                    NavigationLink("自定义词库") { CustomWordsView(model: model) }
                    NavigationLink("键盘外观") { KeyboardAppearanceView(model: model) }
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
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-KeyboardTestMode") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        testFocused = true
                    }
                }
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


struct KeyboardAppearanceView: View {
    @ObservedObject var model: AppModel

    private func binding(_ keyPath: WritableKeyPath<KeyboardSettings, Double>) -> Binding<Double> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.setAppearance(keyPath, $0) }
        )
    }

    var body: some View {
        Form {
            Section("按键") {
                appearanceSlider("圆角", value: binding(\.keyCornerRadius), range: 0...16, format: "%.0f pt")
                appearanceSlider("按键透明度", value: binding(\.keyOpacity), range: 0.3...1, format: "%.2f")
                appearanceSlider("边框透明度", value: binding(\.keyBorderOpacity), range: 0...0.6, format: "%.2f")
                appearanceSlider("键间距", value: binding(\.keySpacing), range: 0...8, format: "%.1f pt")
                appearanceSlider("按键大小", value: binding(\.keyFontScale), range: 0.8...1.2, format: "%.2f×")
                appearanceSlider("触摸扩展", value: binding(\.keyHitExpansion), range: 0...5, format: "%.1f pt")
                appearanceSlider("触感强度", value: binding(\.hapticStrength), range: 0.4...1.2, format: "%.2f×")
                appearanceSlider("背景浓度", value: binding(\.backgroundOpacity), range: 0.2...1, format: "%.2f")
            }
            Section {
                appearanceSlider("键盘高度", value: binding(\.keyboardHeight), range: 240...340, format: "%.0f pt")
                appearanceSlider("左右内缩", value: binding(\.keyboardHorizontalInset), range: 0...24, format: "%.0f pt")
                Button("恢复默认外观") { model.resetAppearance() }
            } header: {
                Text("键盘")
            } footer: {
                Text("外观设置会写入 App Group；免费签名不支持 App Group 时使用本机剪贴板桥接。键盘下次显示时生效。")
            }
        }
        .navigationTitle("键盘外观")
    }

    private func appearanceSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
