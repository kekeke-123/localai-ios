import SwiftUI

struct ChatView: View {

    @EnvironmentObject private var session: ChatSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var voice: VoiceInput

    @State private var showError = false
    @State private var showMore = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                conversation
                statusLines
                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMore) {
            MoreView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(session)
        }
        .alert("出问题了", isPresented: $showError) {
            Button("知道了", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
        .onChange(of: session.lastError) { _, newValue in
            showError = newValue != nil
        }
        .onChange(of: voice.isRecording) { _, isRecording in
            if !isRecording, !voice.transcript.isEmpty {
                session.draft = voice.transcript
            }
        }
        .onChange(of: voice.lastError) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            session.lastError = newValue
            voice.lastError = nil
        }
    }

    // MARK: 背景

    private var background: some View {
        ZStack {
            Color.black
            if session.messages.isEmpty {
                // 只在欢迎页画动态光球，进入对话后换成静态渐变，省 GPU
                SiriOrb(active: voice.isRecording || session.isGenerating)
                    .frame(width: 420, height: 420)
                    .opacity(0.55)
                    .blur(radius: 70)
                    .offset(y: 120)
            } else {
                RadialGradient(colors: [Color(red: 0.35, green: 0.28, blue: 0.85).opacity(0.28), .clear],
                               center: .bottom, startRadius: 10, endRadius: 520)
                    .offset(y: 120)
            }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.36, blue: 1),
                                              Color(red: 0.92, green: 0.36, blue: 0.78)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
            Text("小模")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button {
                showMore = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: 对话区

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if session.messages.isEmpty {
                        greeting
                    }
                    ForEach(session.messages) { message in
                        SiriMessage(message: message)
                            .id(message.id)
                    }
                    if session.isGenerating {
                        HStack(spacing: 10) {
                            SiriOrb(active: true)
                                .frame(width: 34, height: 34)
                            Text("正在想…")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 30)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: session.messages.last?.text ?? "") { _, _ in
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var greeting: some View {
        VStack(spacing: 26) {
            SiriOrb(active: voice.isRecording)
                .frame(width: 190, height: 190)
                .padding(.top, 40)

            VStack(spacing: 8) {
                Text("你好，我是小模")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white)
                Text("模型就在这台手机上跑，聊天内容不上传")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 10) {
                chip("今天有什么科技新闻？")
                chip("简单解释一下什么是黑洞")
                chip("帮我把这段话改得更通顺")
            }
            .padding(.top, 4)

            if let model = ModelCatalog.model(withID: settings.selectedChatModelID),
               !store.isDownloaded(model) {
                Text("还没下载对话模型，点右上角 ⋯ 去「模型」页装一个。")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ text: String) -> some View {
        Button {
            session.draft = text
        } label: {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: 状态行

    @ViewBuilder
    private var statusLines: some View {
        if !session.statusText.isEmpty || voice.isRecording {
            VStack(spacing: 6) {
                if voice.isRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color(red: 0.92, green: 0.36, blue: 0.78))
                        Text(voice.transcript.isEmpty ? "在听…" : voice.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                        Spacer()
                    }
                }
                if !session.statusText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(session.statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    // MARK: 输入条

    private var inputBar: some View {
        VStack(spacing: 8) {
            GlassBar {
                HStack(spacing: 6) {
                    Button {
                        settings.autoSearch.toggle()
                    } label: {
                        Image(systemName: settings.autoSearch ? "globe.americas.fill" : "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(settings.autoSearch ? Color(red: 0.42, green: 0.36, blue: 1) : .white.opacity(0.45))
                            .frame(width: 32, height: 36)
                    }

                    TextField("问点什么…", text: $session.draft, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .lineLimit(1...4)
                        .disabled(session.isGenerating)

                    Button {
                        voice.toggle()
                    } label: {
                        Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 16))
                            .foregroundStyle(voice.isRecording ? Color(red: 0.92, green: 0.36, blue: 0.78) : .white.opacity(0.45))
                            .frame(width: 32, height: 36)
                    }

                    if session.isGenerating {
                        Button {
                            session.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                    } else {
                        Button {
                            let text = session.draft
                            Task { await session.send(text, settings: settings, store: store) }
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    LinearGradient(colors: [Color(red: 0.55, green: 0.42, blue: 1),
                                                            Color(red: 0.92, green: 0.36, blue: 0.78)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle()
                                )
                                .opacity(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                        }
                        .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 18)

            Text("全部在本机运行 · 只有搜索时才联网")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 6)
        }
        .padding(.top, 6)
    }
}

// MARK: - 消息样式

struct SiriMessage: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text.isEmpty ? "…" : message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            } else {
                Text(message.text.isEmpty ? "…" : message.text)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.white)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !message.sources.isEmpty {
                    SourceList(results: message.sources)
                }
            }
        }
    }
}

struct SourceList: View {
    let results: [WebResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("参考来源")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.4))
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                Text("[\(index + 1)] \(item.title)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - 「更多」面板：识图 / 模型 / 设置

struct MoreView: View {

    @EnvironmentObject private var session: ChatSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        VisionView { text in
                            session.draft = text
                            dismiss()
                        }
                    } label: {
                        Label("识图（视觉模型）", systemImage: "photo.fill")
                    }
                    NavigationLink {
                        ModelsView()
                    } label: {
                        Label("模型", systemImage: "square.stack.3d.up.fill")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
