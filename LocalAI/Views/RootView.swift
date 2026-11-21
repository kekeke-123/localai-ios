import SwiftUI

struct RootView: View {

    @StateObject private var settings = AppSettings()
    @StateObject private var store = ModelStore()
    @StateObject private var packStore = VisionPackStore()
    @StateObject private var session = ChatSession()
    @StateObject private var vlm = VlmSession()
    @StateObject private var voice = VoiceInput()

    var body: some View {
        ChatView()
            .environmentObject(settings)
            .environmentObject(store)
            .environmentObject(packStore)
            .environmentObject(session)
            .environmentObject(vlm)
            .environmentObject(voice)
            .preferredColorScheme(.dark)
    }
}
