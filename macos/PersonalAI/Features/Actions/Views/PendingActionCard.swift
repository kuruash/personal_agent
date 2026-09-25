import SwiftUI

struct PendingActionCard: View {
    let action: PendingAction
    let onCancel: () -> Void
    let onApprove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label(action.summary, systemImage: action.isDestructive ? "trash" : "calendar.badge.clock")
                .font(.headline).foregroundStyle(action.isDestructive ? .red : .primary)
            ForEach(action.details, id: \.self) { Text($0).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Cancel", action: onCancel).buttonStyle(.bordered); Button(approveTitle, role: action.isDestructive ? .destructive : nil, action: onApprove).buttonStyle(.borderedProminent) }
        }
        .padding(AppSpacing.large)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(action.isDestructive ? Color.red.opacity(0.45) : AppColors.subtleBorder, lineWidth: 1) }
    }
    private var approveTitle: String { switch action.kind { case .calendarCreate: "Create Event"; case .calendarUpdate: "Update Event"; case .calendarDelete: "Delete Event" } }
}
