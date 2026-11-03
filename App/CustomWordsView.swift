import PrivateKeyboardCore
import SwiftUI

struct CustomWordsView: View {
    @ObservedObject var model: AppModel
    @State private var word = ""
    @State private var pinyin = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("中文词", text: $word)
                TextField("拼音，例如 ni hao", text: $pinyin)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("释义/提示（可选）", text: $note)
                Button("添加自定义词") {
                    errorMessage = model.addCustomWord(word: word, pinyin: pinyin, note: note)
                    if errorMessage == nil {
                        word = ""
                        pinyin = ""
                        note = ""
                    }
                }
                .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty ||
                          pinyin.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("添加")
            } footer: {
                Text("只保存在 App Group 本地；键盘扩展按完整拼音或简拼匹配。")
            }

            Section {
                if model.customWords.isEmpty {
                    Text("还没有自定义词")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.customWords) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.word)
                                Spacer()
                                Text(entry.pinyin)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexes in
                        for index in indexes {
                            model.removeCustomWord(id: model.customWords[index].id)
                        }
                    }
                }
            } header: {
                Text("我的词库")
            }
        }
        .navigationTitle("自定义词库")
        .onAppear { model.reloadCustomWords() }
        .alert("无法添加", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
