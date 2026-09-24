import Foundation

extension Notification.Name {
    static let memoryStoreDidChange = Notification.Name("MemoryStoreDidChange")
}

final class MemoryStore: @unchecked Sendable {
    private let repository: MemoryRepository
    private let notificationCenter: NotificationCenter

    init(repository: MemoryRepository, notificationCenter: NotificationCenter = .default) {
        self.repository = repository
        self.notificationCenter = notificationCenter
    }

    convenience init(database: DatabaseManager) {
        self.init(repository: MemoryRepository(database: database))
    }

    func memory(id: UUID) throws -> MemoryRecord? { try repository.get(id: id) }

    func list(type: MemoryType? = nil, limit: Int = 50) throws -> [MemoryRecord] {
        try repository.list(type: type, limit: min(max(limit, 1), 100))
    }

    func search(_ query: String, type: MemoryType? = nil, limit: Int = 20) throws -> [MemoryRecord] {
        try repository.search(query, type: type, limit: min(max(limit, 1), 50))
    }

    @discardableResult
    func create(
        content: String,
        type: MemoryType,
        source: MemorySource,
        importance: MemoryImportance = .normal
    ) throws -> MemorySaveResult {
        let result = try repository.create(
            content: content, type: type, source: source, importance: importance
        )
        if result.wasCreated { notifyChange() }
        return result
    }

    @discardableResult
    func update(
        id: UUID,
        content: String,
        type: MemoryType,
        importance: MemoryImportance,
        source: MemorySource? = nil
    ) throws -> MemoryRecord {
        let memory = try repository.update(
            id: id, content: content, type: type,
            importance: importance, source: source
        )
        notifyChange()
        return memory
    }

    func delete(id: UUID) throws {
        try repository.delete(id: id)
        notifyChange()
    }

    private func notifyChange() {
        notificationCenter.post(name: .memoryStoreDidChange, object: self)
    }
}
