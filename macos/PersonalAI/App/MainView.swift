import SwiftUI

struct MainView: View {
    @State private var destination: AppDestination? = .assistant
    @State private var sidebarMode: SidebarMode = .expanded
    @State private var prompt = ""
    @State private var attachments: [ChatAttachment] = []
    @ObservedObject private var conversationStore: ConversationStore
    @StateObject private var agent: AgentViewModel

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
        _agent = StateObject(wrappedValue: AgentViewModel(conversationStore: conversationStore))
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarContainer(
                mode: $sidebarMode,
                conversations: conversationStore.conversations,
                selectedConversationID: selectedConversationBinding,
                destination: $destination,
                onNewChat: startNewChat,
                onRenameConversation: agent.renameConversation,
                onDeleteConversation: deleteConversation
            )

            Divider()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.18), value: sidebarMode)
        .alert("Conversation Storage", isPresented: storageErrorBinding) {
            Button("OK") { conversationStore.dismissError() }
        } message: {
            Text(conversationStore.lastErrorDescription ?? "Conversation storage is unavailable.")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch destination ?? .assistant {
        case .assistant:
            ChatView(prompt: $prompt, attachments: $attachments, agent: agent)
        case .profile:
            if let profileStore = conversationStore.profileStore {
                ProfileView(store: profileStore)
            } else {
                DetailPage(title: "Profile", subtitle: "Information Personal AI can use to assist you.") {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Profile unavailable",
                        description: "Local profile storage could not be initialized."
                    )
                }
            }
        case .memory:
            MemoryView()
        case .skills:
            SkillsView()
        case .settings:
            SettingsView(agent: agent)
        }
    }

    private func startNewChat() {
        destination = .assistant
        prompt = ""
        attachments = []
        agent.startNewConversation()
    }

    private func deleteConversation(_ id: UUID) {
        let wasCurrentConversation = agent.currentConversationID == id
        if agent.deleteConversation(id: id), wasCurrentConversation {
            prompt = ""
            destination = .assistant
        }
    }

    private var selectedConversationBinding: Binding<UUID?> {
        Binding(
            get: { agent.currentConversationID },
            set: { id in
                guard let id else { return }
                prompt = ""
                attachments = []
                destination = .assistant
                agent.selectConversation(id: id)
            }
        )
    }

    private var storageErrorBinding: Binding<Bool> {
        Binding(
            get: { conversationStore.lastErrorDescription != nil },
            set: { isPresented in
                if !isPresented { conversationStore.dismissError() }
            }
        )
    }
}

#Preview {
    MainView(conversationStore: .makeDefault())
        .environmentObject(AppearanceStore())
        .frame(width: 1080, height: 720)
}
