import SwiftUI
import UIKit
import PhotosUI

struct VisionView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var packStore: VisionPackStore
    @EnvironmentObject private var vlm: VlmSession
    @EnvironmentObject private var session: ChatSession

    var onSendToChat: (String) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var analysis: VisionAnalysis?
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var question: String = ""

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
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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

                    if image != nil {
                        vlmSection
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
            Text("上面那块由系统 Apple Vision 提供，不需要下载，擅长认物、认字、读条码。"
                 + "下面那块是真正的视觉大模型（SmolVLM），能读画面内容、回答你提的问题，需要单独下载模型包。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var currentPack: VisionPack? {
        VisionPacks.all.first { $0.id == settings.selectedVisionPackID }
    }

    private var vlmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("让视觉模型看图")
                    .font(.headline)
                Spacer()
                if let pack = currentPack {
                    Text(pack.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let pack = currentPack, packStore.isInstalled(pack) {
                TextField("想问什么？例如：图里的人在做什么 / 帮我数一下有几个", text: $question, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        Task { await runVlm(pack) }
                    } label: {
                        Label(vlm.isRunning ? "生成中…" : "开始描述", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(vlm.isRunning ? 0.08 : 0.18),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(vlm.isRunning)

                    if vlm.isRunning {
                        Button {
                            vlm.stop()
                        } label: {
                            Text("停止")
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !vlm.statusText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(vlm.statusText).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !vlm.answer.isEmpty {
                    Text(vlm.answer)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        onSendToChat(vlm.answer)
                    } label: {
                        Label("把这段描述发给小模继续问", systemImage: "paperplane")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                if let error = vlm.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } else {
                Text("还没有安装视觉模型。到「模型」页下载「视觉模型·小」（约 279 MB），装好后这里就能真正看图说话了。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func runVlm(_ pack: VisionPack) async {
        guard let image else { return }
        // 同屏只留一个重模型，先把对话模型卸掉，避免内存炸
        session.unload()
        await vlm.describe(image: image,
                           question: question,
                           pack: pack,
                           packStore: packStore,
                           settings: settings)
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
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
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
