import SwiftUI

@main
struct PersonalAIApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @StateObject private var conversationStore: ConversationStore

    init() {
        _conversationStore = StateObject(wrappedValue: ConversationStore.makeDefault())
    }

    var body: some Scene {
        WindowGroup {
            MainView(conversationStore: conversationStore)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}
