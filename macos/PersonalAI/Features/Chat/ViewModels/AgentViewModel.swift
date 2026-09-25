import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var state: AgentExecutionState?
    @Published private(set) var isWorking = false
    @Published private(set) var approvedDirectories: [ApprovedDirectory] = []
    @Published private(set) var selectedModelID: String?
    @Published private(set) var currentConversationID: UUID?
    @Published private(set) var pendingAction: PendingAction?

    let providerName = "Nebius Token Factory"
    let conversationStore: ConversationStore

    private let fileAccessPolicy = FileAccessPolicy.shared
    private var runtime: AgentRuntime?
    private var currentModelHistory: [ChatMessage] = []
    private var policyObservation: AnyCancellable?
    private var pendingActionObservation: AnyCancellable?
    private var sessionID = UUID()

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
        approvedDirectories = fileAccessPolicy.userApprovedDirectories
        policyObservation = NotificationCenter.default
            .publisher(for: .fileAccessPolicyDidChange, object: fileAccessPolicy)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.approvedDirectories = self?.fileAccessPolicy.userApprovedDirectories ?? []
            }
        if let pendingStore = conversationStore.pendingActionStore {
            pendingActionObservation = pendingStore.$pendingAction
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.pendingAction = $0 }
        }
    }

    func submit(_ message: String, attachments: [ChatAttachment] = []) {
        guard !isWorking else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        if currentConversationID == nil {
            let conversation = Conversation(
                title: ConversationStore.title(from: trimmedMessage)
            )
            currentConversationID = conversation.id
        }

        let submittedSessionID = sessionID
        messages.append(ConversationMessage(role: .user, content: trimmedMessage))
        persistCurrentConversation()
        errorMessage = nil
        isWorking = true

        Task {
            do {
                let runtime = try makeRuntimeIfNeeded()
                let viewModel = self
                let hasVisualInput = attachments.contains { attachment in
                    attachment.contentTypeIdentifier.flatMap(UTType.init)?.conforms(to: .image) == true
                }
                let answer = try await runtime.send(userMessage: trimmedMessage, hasVisualInput: hasVisualInput) { state in
                    await viewModel.updateState(state, for: submittedSessionID)
                }
                guard sessionID == submittedSessionID else { return }
                selectedModelID = await runtime.currentModelID()
                messages.append(ConversationMessage(role: .assistant, content: answer))
                persistCurrentConversation(modelHistory: await runtime.historyForPersistence())
            } catch {
                guard sessionID == submittedSessionID else { return }
                if let runtime {
                    selectedModelID = await runtime.currentModelID()
                }
                errorMessage = error.localizedDescription
                messages.append(ConversationMessage(
                    role: .assistant,
                    content: userFacingErrorMessage(for: error)
                ))
                // Never persist an incomplete assistant-tool exchange after a failed turn.
                persistCurrentConversation(modelHistory: modelHistoryFromVisibleMessages())
            }
            if sessionID == submittedSessionID {
                isWorking = false
            }
        }
    }

    func startNewConversation() {
        sessionID = UUID()
        currentConversationID = nil
        messages = []
        errorMessage = nil
        state = nil
        isWorking = false
        // A new runtime guarantees fresh model history. Any in-flight response from the
        // previous conversation is ignored via conversationID above.
        runtime = nil
        currentModelHistory = []
    }

    func selectConversation(id: UUID) {
        // Invalidate any response for the previous conversation and clear its
        // visible messages before performing the SQLite-backed selection load.
        sessionID = UUID()
        currentConversationID = id
        messages = []
        currentModelHistory = []
        errorMessage = nil
        state = nil
        isWorking = false
        runtime = nil

        guard let conversation = conversationStore.loadConversation(id: id) else {
            currentConversationID = nil
            return
        }
        activate(conversation)
    }

    private func activate(_ conversation: Conversation) {
        sessionID = UUID()
        currentConversationID = conversation.id
        messages = conversation.messages
        currentModelHistory = conversation.modelHistory
        errorMessage = nil
        state = nil
        isWorking = false
        runtime = nil
    }

    func renameConversation(id: UUID, title: String) {
        conversationStore.rename(id: id, title: title)
    }

    @discardableResult
    func deleteConversation(id: UUID) -> Bool {
        let deletingCurrent = currentConversationID == id
        let deletedIndex = conversationStore.conversations.firstIndex { $0.id == id }
        guard conversationStore.delete(id: id) else { return false }

        guard deletingCurrent else { return true }
        let remaining = conversationStore.conversations
        if !remaining.isEmpty {
            let index = min(deletedIndex ?? 0, remaining.count - 1)
            activate(remaining[index])
        } else {
            startNewConversation()
        }
        return true
    }

    func chooseReadOnlyDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Allow Read-Only Folder Access"
        panel.message = "Personal AI will only be able to read files inside the selected folder."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self?.fileAccessPolicy.approveUserSelectedDirectory(url)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func removeReadOnlyDirectory(_ directory: ApprovedDirectory) {
        do {
            try fileAccessPolicy.removeUserSelectedDirectory(path: directory.path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPendingAction(_ action: PendingAction) { conversationStore.pendingActionStore?.cancel(id: action.id) }

    func approvePendingAction(_ action: PendingAction) {
        guard let action = conversationStore.pendingActionStore?.takeForApproval(id: action.id), let calendarStore = conversationStore.calendarStore else { return }
        do {
            let event = try calendarStore.perform(action.calendarMutation)
            let response: String
            switch (action.calendarMutation, event) {
            case (.create(let draft), let created?): response = "Created **\(created.title)** for \(CalendarPresentation.dateRange(start: draft.startDate, end: draft.endDate, allDay: draft.isAllDay))."
            case (.update, let updated?): response = "Updated **\(updated.title)** to \(CalendarPresentation.dateRange(start: updated.startDate, end: updated.endDate, allDay: updated.isAllDay))."
            case (.delete, _): response = "Deleted the selected calendar event."
            default: response = "Calendar change completed."
            }
            messages.append(ConversationMessage(role: .assistant, content: response)); persistCurrentConversation()
        } catch {
            messages.append(ConversationMessage(role: .assistant, content: "I couldn't complete that calendar change. Please confirm the event and Calendar access, then try again.")); persistCurrentConversation()
        }
    }

    private func makeRuntimeIfNeeded() throws -> AgentRuntime {
        if let runtime { return runtime }
        let persistedHistory = currentModelHistory
        // submit() has already appended the current user message; AgentRuntime.send will
        // append it to model history, so fallback restoration must exclude that one message.
        let restoredHistory = persistedHistory.isEmpty
            ? modelHistoryFromVisibleMessages(excludingLastUser: true)
            : persistedHistory
        let newRuntime = AgentRuntime(
            client: try NebiusClient(),
            restoredHistory: restoredHistory,
            conversationID: currentConversationID,
            profileStore: conversationStore.profileStore,
            memoryStore: conversationStore.memoryStore,
            calendarStore: conversationStore.calendarStore,
            pendingActionStore: conversationStore.pendingActionStore
        )
        runtime = newRuntime
        return newRuntime
    }

    private func updateState(_ state: AgentExecutionState, for sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.state = state
    }

    private func persistCurrentConversation(modelHistory: [ChatMessage]? = nil) {
        guard let currentConversationID else { return }
        if let modelHistory { currentModelHistory = modelHistory }
        let existing = conversationStore.conversation(id: currentConversationID)
        let firstUserMessage = messages.first(where: { $0.role == .user })?.content ?? "Conversation"
        let conversation = Conversation(
            id: currentConversationID,
            title: existing?.title ?? ConversationStore.title(from: firstUserMessage),
            messages: messages,
            modelHistory: modelHistory ?? currentModelHistory,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        conversationStore.save(conversation)
    }

    private func modelHistoryFromVisibleMessages(excludingLastUser: Bool = false) -> [ChatMessage] {
        var visibleMessages = messages
        if excludingLastUser, visibleMessages.last?.role == .user {
            visibleMessages.removeLast()
        }
        return visibleMessages.map { message in
            ChatMessage(
                role: message.role == .user ? "user" : "assistant",
                content: message.content
            )
        }
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        switch error {
        case NebiusClientError.missingAPIKey:
            return "I couldn't connect to Nebius. Add the API key to the app's environment and try again."
        case AgentRuntimeError.noNemotronModel:
            return "I couldn't find an available NVIDIA Nemotron model. Please try again later."
        default:
            return "I couldn't complete that request. Please try again. If the problem continues, check the app's connection and folder permissions."
        }
    }
}
