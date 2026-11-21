import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var session: ChatSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("搜索来源", selection: $settings.searchProvider) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    Toggle("每次提问自动联网搜索", isOn: $settings.autoSearch)
                } header: {
                    Text("联网搜索")
                } footer: {
                    Text("搜索只在你主动开启时发生，提问内容会发给搜索引擎；其余对话全部留在本地。")
                }

                Section {
                    Picker("对话模型", selection: $settings.selectedChatModelID) {
                        ForEach(ModelCatalog.chatModels) { model in
                            Text(store.isDownloaded(model) ? model.name : "\(model.name)（未下载）")
                                .tag(model.id)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("温度")
                            Spacer()
                            Text(String(format: "%.2f", settings.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.temperature, in: 0.1...1.2, step: 0.05)
                    }

                    Stepper("上下文长度：\(settings.contextLength)",
                            value: $settings.contextLength, in: 1024...8192, step: 1024)

                    Stepper("单次回答上限：\(settings.maxTokens) 字",
                            value: $settings.maxTokens, in: 128...1024, step: 64)
                } header: {
                    Text("生成参数")
                } footer: {
                    Text("上下文越长越吃内存。手机内存有限，1.5B 模型建议不要超过 4096。")
                }

                Section {
                    Text("存储位置：App 沙盒内的 Models 文件夹。可用「文件」App 查看，路径为 我的 iPhone → 本地智能。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("数据")
                }

                Section {
                    Text("Siri AI · 27.0.1")
                        .font(.footnote)
                    Text(SiriPlusKernel.name + " " + SiriPlusKernel.version)
                        .font(.footnote.weight(.semibold))
                    Text("推理内核：\(SiriPlusKernel.tagline)\n\(SiriPlusKernel.base)\n识图：Apple Vision（完全离线）\n搜索：必应 / DuckDuckGo 网页版")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
