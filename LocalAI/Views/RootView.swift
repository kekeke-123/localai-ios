import SwiftUI

struct RootView: View {

    @StateObject private var settings = AppSettings()
    @StateObject private var store = ModelStore()
    @StateObject private var packStore = VisionPackStore()
    @StateObject private var session = ChatSession()
    @StateObject private var vlm = VlmSession()
    @StateObject private var voice = VoiceInput()

    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            ChatView()
                .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(0)

            VisionView { text in
                session.draft = text
                tab = 0
            }
            .tabItem { Label("识图", systemImage: "photo.fill") }
            .tag(1)

            ModelsView()
                .tabItem { Label("模型", systemImage: "square.stack.3d.up.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .environmentObject(settings)
        .environmentObject(store)
        .environmentObject(packStore)
        .environmentObject(session)
        .environmentObject(vlm)
        .environmentObject(voice)
    }
}
