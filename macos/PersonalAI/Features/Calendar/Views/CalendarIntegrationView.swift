import SwiftUI
import os

struct CalendarIntegrationView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "CalendarIntegrationView"
    )
    @ObservedObject var store: CalendarStore

    var body: some View {
        DetailPage(title: "Calendar", subtitle: "Allow Personal AI to view and manage calendar events.") {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("STATUS").font(AppTypography.sectionLabel).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        HStack { Image(systemName: statusIcon).foregroundStyle(statusColor); Text(statusTitle).font(.headline); Spacer() }
                        Text(statusDescription).foregroundStyle(.secondary)
                        if let message = store.permissionErrorMessage {
                            Text(message).font(.callout).foregroundStyle(.red)
                        }
                        if store.authorizationStatus == .authorized { Text("Calendars available: \(store.calendarCount)").font(.callout).foregroundStyle(.secondary) }
                        actionButton
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppColors.subtleBorder, lineWidth: 1) }
                }
                Spacer()
            }
            .frame(maxWidth: 700, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { store.refreshStatus() }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if store.authorizationStatus == .notDetermined {
            Button("Connect Calendar") {
                #if DEBUG
                Self.logger.debug("Connect Calendar clicked")
                #endif
                Task { await store.connect() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isRequestingAccess)
        } else {
            Button("Refresh Status") { store.refreshStatus() }.buttonStyle(.bordered)
        }
    }
    private var statusTitle: String { switch store.authorizationStatus { case .notDetermined: "Not Connected"; case .authorized: "Connected"; case .denied: "Access Denied"; case .restricted: "Access Restricted"; case .unavailable: "Unavailable" } }
    private var statusDescription: String { switch store.authorizationStatus { case .notDetermined: "Connect Calendar when you are ready to let Personal AI view and manage events."; case .authorized: "Personal AI can view and manage events. Every change requires your approval."; case .denied: "Personal AI cannot access your calendar until permission is enabled in macOS System Settings."; case .restricted: "Calendar access is restricted by macOS or an administrator."; case .unavailable: "Calendar access is unavailable for this account or macOS configuration." } }
    private var statusIcon: String { store.authorizationStatus == .authorized ? "checkmark.circle.fill" : "calendar.badge.exclamationmark" }
    private var statusColor: Color { store.authorizationStatus == .authorized ? .green : .secondary }
}
