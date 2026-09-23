import SwiftUI

struct ConversationView: View {
    @Binding var prompt: String
    @ObservedObject var agent: AgentViewModel

    private let bottomID = "conversation-bottom"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(agent.messages.enumerated()), id: \.element.id) { index, message in
                            ChatMessageView(message: message)
                                .id(message.id)
                                .padding(.top, messageSpacing(at: index))
                        }

                        if agent.isWorking {
                            workingIndicator
                                .id("agent-working")
                                .padding(.top, AppSpacing.medium)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, AppSpacing.xxLarge)
                    .padding(.vertical, AppSpacing.xLarge)
                }
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: agent.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: agent.isWorking) { _, isWorking in
                    if isWorking { scrollToBottom(proxy) }
                }
            }

            Divider()

            ChatComposer(text: $prompt, isWorking: agent.isWorking, onSubmit: agent.submit)
                .frame(maxWidth: 760)
                .padding(.horizontal, AppSpacing.xxLarge)
                .padding(.vertical, AppSpacing.medium)
        }
    }

    private var workingIndicator: some View {
        HStack(alignment: .top, spacing: AppSpacing.small) {
            Image(systemName: "sparkle")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text("Personal AI")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: AppSpacing.small) {
                    ProgressView()
                        .controlSize(.small)
                    Text(workingStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal AI, \(workingStatus)")
    }

    private var workingStatus: String {
        guard let state = agent.state else { return "Thinking…" }
        switch state {
        case .thinking:
            return "Thinking…"
        case .callingTool(let name):
            switch name {
            case "search_files": return "Searching files…"
            case "read_file": return "Reading file…"
            case "list_directory": return "Checking folder…"
            case "get_file_info": return "Checking file information…"
            case "get_current_project": return "Checking project information…"
            default: return "Using a local tool…"
            }
        case .toolCompleted:
            return "Processing tool results…"
        case .generatingResponse:
            return "Generating response…"
        case .completed:
            return "Completing response…"
        case .failed:
            return "Unable to complete the request."
        }
    }

    private func messageSpacing(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let message = agent.messages[index]
        let previous = agent.messages[index - 1]
        if message.role == .assistant, previous.role == .user {
            return AppSpacing.medium
        }
        return AppSpacing.xLarge + AppSpacing.small
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }
}
