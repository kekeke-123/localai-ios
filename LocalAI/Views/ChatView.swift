import SwiftUI

struct ChatView: View {

    @EnvironmentObject private var session: ChatSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore

    @State private var showError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let model = ModelCatalog.model(withID: settings.selectedChatModelID),
                   !store.isDownloaded(model) {
                    noticeBar("还没下载对话模型，去「模型」页下载一个才能聊天。")
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if session.messages.isEmpty {
                                emptyState
                            }
                            ForEach(session.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .onChange(of: session.messages.count) { _, _ in
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: session.messages.last?.text ?? "") { _, _ in
                        scrollToBottom(proxy, animated: false)
                    }
                }

                if !session.statusText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(session.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }

                inputBar
            }
            .navigationTitle("本地智能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("清空对话", role: .destructive) { session.clear() }
                        if let name = session.currentModelName {
                            Text("当前模型：\(name)")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("出问题了", isPresented: $showError) {
                Button("知道了", role: .cancel) { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
            .onChange(of: session.lastError) { _, newValue in
                showError = newValue != nil
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = session.messages.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你好，我是小模")
                .font(.title2.weight(.semibold))
            Text("我跑在这台手机上，模型文件也在本地，聊天内容不会上传。需要查网上资料时，才会去搜索。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("试试问：帮我把这段话改得更通顺 / 简单解释一下什么是黑洞 / 今天有什么科技新闻")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .padding(.bottom, 10)
    }

    private func noticeBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text).font(.footnote)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    settings.autoSearch.toggle()
                } label: {
                    Image(systemName: settings.autoSearch ? "globe.americas.fill" : "globe")
                        .font(.system(size: 18))
                        .foregroundStyle(settings.autoSearch ? Color.accentColor : Color.secondary)
                        .frame(width: 34, height: 34)
                }

                TextField("问点什么…", text: $session.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .disabled(session.isGenerating)

                if session.isGenerating {
                    Button {
                        session.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.red, in: Circle())
                    }
                } else {
                    Button {
                        let text = session.draft
                        Task { await session.send(text, settings: settings, store: store) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(session.draft.isEmpty ? Color.gray : Color.accentColor, in: Circle())
                    }
                    .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.text.isEmpty ? "…" : message.text)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                                              : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                if !message.sources.isEmpty {
                    SourceList(results: message.sources)
                }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

struct SourceList: View {
    let results: [WebResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("参考来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                Text("[\(index + 1)] \(item.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
    }
}
