import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {

    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var settings: AppSettings

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var imported: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    modelRow(ModelCatalog.visionModel)
                } header: {
                    Text("视觉（识图）")
                } footer: {
                    Text("系统自带，用来认物、认字、读条码。不需要下载。")
                }

                Section {
                    ForEach(ModelCatalog.chatModels) { model in
                        modelRow(model)
                    }
                } header: {
                    Text("对话（本地大模型）")
                } footer: {
                    Text("模型文件保存在 App 自己的目录里，删掉 App 就一起没了。第一次使用需要联网下载一次，之后完全离线。")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("从「文件」导入 GGUF 模型", systemImage: "folder.badge.plus")
                    }
                    if !imported.isEmpty {
                        ForEach(imported, id: \.self) { name in
                            HStack {
                                Text(name).font(.footnote)
                                Spacer()
                                Text(sizeText(forFile: name))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("自定义")
                } footer: {
                    Text("支持任何 llama.cpp 能跑的 GGUF 模型。中小模型（0.5B～1.5B）在手机上比较合适。")
                }
            }
            .navigationTitle("模型")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { imported = store.importedFiles() }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importMessage = store.importFile(from: url)
                        imported = store.importedFiles()
                    }
                case .failure(let error):
                    importMessage = "导入失败：\(error.localizedDescription)"
                }
            }
            .alert("提示", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("好", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func sizeText(forFile name: String) -> String {
        let url = store.modelsDirectory.appendingPathComponent(name)
        var size: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let value = attributes[.size] as? Int64 {
            size = value
        }
        return String(format: "%.0f MB", Double(size) / 1024.0 / 1024.0)
    }

    @ViewBuilder
    private func modelRow(_ model: CatalogModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.headline)
                        if model.kind == .chat, settings.selectedChatModelID == model.id {
                            Text("使用中")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(model.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(store.fileSizeText(model))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actionButton(for: model)
            }

            if let fraction = store.progress[model.id] {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text("正在下载 \(Int(fraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = store.errorText[model.id] {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionButton(for model: CatalogModel) -> some View {
        if model.isBuiltin {
            Text("内置")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if store.isDownloading(model) {
            Button("取消") { store.cancelDownload(model) }
                .buttonStyle(.bordered)
        } else if store.isDownloaded(model) {
            Menu {
                Button("设为当前对话模型") {
                    settings.selectedChatModelID = model.id
                }
                Button("删除模型文件", role: .destructive) {
                    store.delete(model)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Button("下载") { store.download(model) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
