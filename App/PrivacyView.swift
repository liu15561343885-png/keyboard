import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("数据不会离开这台设备")
                    .font(.title2.bold())
                Text("PrivateKeyboard 不上传正在输入的文字、按键、上下文或个人词频，不接入广告或第三方统计 SDK，不包含语音输入。")
                    .font(.callout)

                dataFlow

                Group {
                    Text("键盘扩展").font(.headline)
                    Text("只读取 App Group 中共享的只读词库、二元/三元语言模型、Core ML 模型和本机用户词频。扩展内没有 URLSession、广告或分析代码。关闭网络后仍可输入。")
                    Text("主 App").font(.headline)
                    Text("启动时可按配置检查公开的 manifest.json，仅下载词库、模型及其签名清单。请求中不包含按键、输入内容、上下文、设备标识或用户词频。更新失败会继续使用旧版本。")
                    Text("用户词频").font(.headline)
                    Text("仅写入 App Group 的 user-history.json，可在设置中一键清除。词库更新只由主 App 执行；键盘扩展从不下载数据。")
                }
                .font(.callout)
            }
            .padding()
        }
        .navigationTitle("隐私说明")
    }

    private var dataFlow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("按键 → 本地拼音/切分 → 本地词库/语言模型 → Core ML → 候选栏", systemImage: "keyboard")
            Label("候选选择 → 本机用户词频 → App Group", systemImage: "internaldrive")
            Label("主 App → HTTPS 获取公开 manifest/二进制数据 → SHA-256 + Ed25519 → 原子安装", systemImage: "arrow.down.circle")
            Label("无用户数据上传", systemImage: "icloud.slash")
        }
        .font(.footnote)
        .padding()
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
