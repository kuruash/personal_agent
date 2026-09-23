import SwiftUI

struct MainView: View {
    @State private var destination: AppDestination? = .assistant
    @State private var prompt = ""
    @StateObject private var conversationStore: ConversationStore
    @StateObject private var agent: AgentViewModel

    init(conversationStore: ConversationStore) {
        _conversationStore = StateObject(wrappedValue: conversationStore)
        _agent = StateObject(wrappedValue: AgentViewModel(conversationStore: conversationStore))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                conversations: conversationStore.conversations,
                selectedConversationID: selectedConversationBinding,
                destination: $destination,
                onNewChat: startNewChat,
                onRenameConversation: agent.renameConversation,
                onDeleteConversation: deleteConversation
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
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
            AssistantView(prompt: $prompt, agent: agent)
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
        agent.startNewConversation()
    }

    private func deleteConversation(_ id: UUID) {
        let wasCurrentConversation = agent.currentConversationID == id
        agent.deleteConversation(id: id)
        if wasCurrentConversation {
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
        .frame(width: 1080, height: 720)
}
