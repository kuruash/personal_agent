import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(.quaternary.opacity(0.55), in: Circle())

            VStack(spacing: AppSpacing.xSmall) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: 380)
        .accessibilityElement(children: .combine)
    }
}
