import SwiftUI

struct ChatView: View {
    @Binding var prompt: String
    @Binding var attachments: [ChatAttachment]
    @ObservedObject var agent: AgentViewModel

    var body: some View {
        ZStack {
            AppColors.contentBackground
                .ignoresSafeArea()

            if agent.messages.isEmpty {
                EmptyChatView(prompt: $prompt, attachments: $attachments, agent: agent)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, AppSpacing.xxLarge)
                    .padding(.vertical, AppSpacing.xLarge)
            } else {
                ConversationView(prompt: $prompt, attachments: $attachments, agent: agent)
            }
        }
    }
}
