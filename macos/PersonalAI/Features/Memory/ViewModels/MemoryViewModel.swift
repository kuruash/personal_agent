import Combine
import Foundation

@MainActor
final class MemoryViewModel: ObservableObject {
    @Published private(set) var memories: [MemoryRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var query = ""
    @Published var selectedType: MemoryType?

    private let store: MemoryStore
    private var changeObservation: AnyCancellable?

    init(store: MemoryStore, notificationCenter: NotificationCenter = .default) {
        self.store = store
        changeObservation = notificationCenter.publisher(for: .memoryStoreDidChange, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                memories = try store.list(type: selectedType, limit: 100)
            } else {
                memories = try store.search(query, type: selectedType, limit: 100)
            }
            errorMessage = nil
        } catch {
            memories = []
            errorMessage = "Memories could not be loaded. Please try again."
        }
    }

    @discardableResult
    func create(content: String, type: MemoryType, importance: MemoryImportance) -> Bool {
        do {
            let result = try store.create(content: content, type: type, source: .manualUI, importance: importance)
            guard result.wasCreated else {
                errorMessage = "An identical memory already exists."
                return false
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = userMessage(for: error, fallback: "The memory could not be saved.")
            return false
        }
    }

    @discardableResult
    func update(id: UUID, content: String, type: MemoryType, importance: MemoryImportance) -> Bool {
        do {
            try store.update(id: id, content: content, type: type, importance: importance)
            errorMessage = nil
            return true
        } catch {
            errorMessage = userMessage(for: error, fallback: "The memory could not be updated.")
            return false
        }
    }

    func delete(id: UUID) {
        do {
            try store.delete(id: id)
            errorMessage = nil
        } catch {
            errorMessage = "The memory could not be deleted."
        }
    }

    private func userMessage(for error: Error, fallback: String) -> String {
        guard let memoryError = error as? MemoryError else { return fallback }
        switch memoryError {
        case .duplicate: return "An identical memory already exists."
        default: return memoryError.localizedDescription
        }
    }
}
