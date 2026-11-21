import SwiftUI
import PhotosUI

struct VisionView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore

    var onSendToChat: (String) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analysis: VisionAnalysis?
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(image == nil ? "选择图片" : "换一张", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if image != nil {
                            Button {
                                analysis = nil
                                image = nil
                                pickerItem = nil
                             } label: {
                                Text("清除")
                                    .padding(.vertical, 11)
                                    .padding(.horizontal, 16)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在本地识别…（不联网）")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let analysis {
                        resultCard(analysis)
                    }

                    infoFooter
                }
                .padding(18)
            }
            .navigationTitle("识图")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pickerItem) { _, newValue in
                loadImage(newValue)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内置视觉模型")
                .font(.headline)
            Text("分类、文字识别、条码识别都在手机本地完成，图片不会上传。"
                 + "识别结果可以接着发给本地对话模型，让它用中文解释。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var infoFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("这个视觉模型由系统 Apple Vision 提供，不占用额外存储，也不需要下载。"
                 + "它对物品、场景、常见文字的识别比较稳，但对画面里的细节理解有限——"
                 + "想看更细的描述，需要另配视觉大模型（当前版本还没做）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func resultCard(_ analysis: VisionAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !analysis.labels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("画面元素")
                        .font(.subheadline.weight(.semibold))
                    FlowRow(labels: analysis.labels)
                }
            }

            if !analysis.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("图中文字")
                        .font(.subheadline.weight(.semibold))
                    Text(analysis.recognizedText)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            if !analysis.barcodes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("条码")
                        .font(.subheadline.weight(.semibold))
                    ForEach(analysis.barcodes, id: \.self) { code in
                        Text(code).font(.footnote.monospaced())
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    onSendToChat(analysis.promptDescription)
                } label: {
                    Label("发给小模解释", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = analysis.promptDescription
                } label: {
                    Image(systemName: "doc.on.doc")
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadImage(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isWorking = true
        analysis = nil
        errorText = nil

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else {
                    throw NSError(domain: "VisionView", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "这张图片读不出来。"])
                }
                await MainActor.run { self.image = ui }

                let result = try await ImageAnalyzer.analyze(ui)
                await MainActor.run {
                    self.analysis = result
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.isWorking = false
                }
            }
        }
    }
}

/// 简单的标签流式排列
struct FlowRow: View {
    let labels: [VisionLabel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                HStack(spacing: 8) {
                    Text(label.name)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    Text("\(Int(label.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
