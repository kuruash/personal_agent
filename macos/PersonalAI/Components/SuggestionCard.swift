import SwiftUI

struct SuggestionCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text(title)
                    .font(AppTypography.suggestion)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: 42)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.subtleBorder, lineWidth: 1)
        }
    }
}
