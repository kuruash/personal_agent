import SwiftUI

struct DetailPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(AppTypography.pageTitle)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.xxLarge)
            .padding(.top, AppSpacing.xLarge)
            .padding(.bottom, AppSpacing.large)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppSpacing.xxLarge)
        }
        .background(AppColors.contentBackground)
    }
}
