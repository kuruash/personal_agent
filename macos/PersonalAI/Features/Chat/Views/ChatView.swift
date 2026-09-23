import SwiftUI

struct ChatView: View {
    @Binding var prompt: String
    @ObservedObject var agent: AgentViewModel

    var body: some View {
        ZStack {
            AppColors.contentBackground
                .ignoresSafeArea()

            if agent.messages.isEmpty {
                EmptyChatView(prompt: $prompt, agent: agent)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, AppSpacing.xxLarge)
                    .padding(.vertical, AppSpacing.xLarge)
            } else {
                ConversationView(prompt: $prompt, agent: agent)
            }
        }
    }
}
