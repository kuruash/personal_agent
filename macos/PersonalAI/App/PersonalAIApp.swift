import SwiftUI

@main
struct PersonalAIApp: App {
    @StateObject private var appearanceStore: AppearanceStore
    @StateObject private var conversationStore: ConversationStore

    init() {
        _appearanceStore = StateObject(wrappedValue: AppearanceStore())
        _conversationStore = StateObject(wrappedValue: ConversationStore.makeDefault())
    }

    var body: some Scene {
        WindowGroup {
            MainView(conversationStore: conversationStore)
                .frame(minWidth: 820, minHeight: 560)
                .environmentObject(appearanceStore)
                .background {
                    WindowAppearanceController(appearance: appearanceStore.selection)
                        .frame(width: 0, height: 0)
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}
