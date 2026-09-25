import Combine
import Foundation

@MainActor
final class PendingActionStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var pendingAction: PendingAction?

    func propose(_ action: PendingAction) { pendingAction = action }
    func cancel(id: UUID) { guard pendingAction?.id == id else { return }; pendingAction = nil }

    /// Removes the action before execution, preventing duplicate approvals.
    func takeForApproval(id: UUID, now: Date = Date()) -> PendingAction? {
        guard let action = pendingAction, action.id == id, action.expiresAt > now else {
            if pendingAction?.id == id { pendingAction = nil }
            return nil
        }
        pendingAction = nil
        return action
    }
}
