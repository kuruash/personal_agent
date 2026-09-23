import SwiftUI

struct PromptInputView: View {
    @Binding var text: String
    let isWorking: Bool
    let onSubmit: (String) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            TextField("Ask anything or give me a task...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTypography.prompt)
                .lineLimit(1...5)
                .focused($isFocused)
                .onSubmit(submit)

            HStack {
                Text("Shift ↵ for a new line")
                    .font(AppTypography.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                .help("Send")
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? AppColors.focusBorder : AppColors.subtleBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func submit() {
        let submittedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty, !isWorking else { return }
        text = ""
        onSubmit(submittedText)
    }
}
