import SwiftUI

struct StatusIndicator: View {
    enum Status {
        case ready
        case working(String)
        case completed
        case failed

        var label: String {
            switch self {
            case .ready: "Ready"
            case .working(let label): label
            case .completed: "Completed"
            case .failed: "Failed"
            }
        }

        var color: Color {
            switch self {
            case .ready: .green
            case .working: .orange
            case .completed: .green
            case .failed: .red
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: AppSpacing.xSmall) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(status.label)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(AppColors.subtleBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent status: \(status.label)")
    }
}
