import SwiftUI

struct EmptyChatView: View {
    @Binding var prompt: String
    @Binding var attachments: [ChatAttachment]
    @ObservedObject var agent: AgentViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: AppSpacing.xxLarge)

            Text(greeting)
                .font(AppTypography.greeting)
                .foregroundStyle(.secondary)
                .padding(.bottom, AppSpacing.small)

            Text("What can I help you with?")
                .font(AppTypography.welcomeTitle)
                .multilineTextAlignment(.center)
                .padding(.bottom, AppSpacing.xLarge)

            ChatComposer(
                text: $prompt,
                attachments: $attachments,
                isWorking: agent.isWorking,
                onSubmit: { agent.submit($0, attachments: attachments) }
            )

            Spacer(minLength: AppSpacing.xxLarge)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
