import Foundation
import os

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var lastErrorDescription: String?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "ConversationStore"
    )

    let databaseURL: URL?
    let profileStore: ProfileStore?
    let memoryStore: MemoryStore?
    let calendarStore: CalendarStore?
    let pendingActionStore: PendingActionStore?
    private let repository: ConversationRepository?
    private let fileManager: FileManager

    init(
        database: DatabaseManager,
        legacyStorageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        repository = ConversationRepository(database: database)
        let profileRepository = ProfileRepository(database: database)
        profileStore = ProfileStore(repository: profileRepository)
        memoryStore = MemoryStore(database: database)
        calendarStore = CalendarStore()
        pendingActionStore = PendingActionStore()
        databaseURL = database.databaseURL
        self.fileManager = fileManager
        let migrationError = migrateLegacyJSONIfNeeded(
            at: legacyStorageURL ?? Self.defaultLegacyStorageURL(fileManager: fileManager)
        )
        reload()
        if let migrationError { lastErrorDescription = migrationError }
    }

    static func makeDefault(fileManager: FileManager = .default) -> ConversationStore {
        do {
            return ConversationStore(database: try DatabaseManager(fileManager: fileManager), fileManager: fileManager)
        } catch {
            logger.error("Database initialization failed: \(error.localizedDescription, privacy: .public)")
            return ConversationStore(initializationError: error, fileManager: fileManager)
        }
    }

    private init(initializationError: Error, fileManager: FileManager) {
        repository = nil
        profileStore = nil
        memoryStore = nil
        calendarStore = nil
        pendingActionStore = nil
        databaseURL = nil
        self.fileManager = fileManager
        lastErrorDescription = "Conversation storage could not be initialized."
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Loads the selected conversation from SQLite rather than relying on the
    /// sidebar's in-memory summary/cache.
    func loadConversation(id: UUID) -> Conversation? {
        guard let repository else { return nil }
        do {
            let conversation = try repository.loadConversation(id: id)
            lastErrorDescription = nil
            return conversation
        } catch {
            handle(error, userMessage: "The selected conversation could not be loaded.")
            return nil
        }
    }

    @discardableResult
    func save(_ conversation: Conversation) -> Bool {
        guard conversation.hasMeaningfulContent, let repository else { return false }
        do {
            try repository.save(conversation)
            reload()
            return true
        } catch {
            handle(error, userMessage: "Conversation history could not be saved.")
            return false
        }
    }

    func rename(id: UUID, title: String) {
        let cleanedTitle = Self.cleanedTitle(title)
        guard !cleanedTitle.isEmpty, let repository else { return }
        do {
            try repository.rename(id: id, title: cleanedTitle)
            reload()
        } catch {
            handle(error, userMessage: "The conversation could not be renamed.")
        }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let repository else { return false }
        do {
            try repository.delete(id: id)
            reload()
            return true
        } catch {
            handle(error, userMessage: "The conversation could not be deleted.")
            return false
        }
    }

    func dismissError() {
        lastErrorDescription = nil
    }

    static func title(from firstUserMessage: String, maximumLength: Int = 42) -> String {
        let cleaned = cleanedTitle(firstUserMessage)
        guard cleaned.count > maximumLength else { return cleaned }
        let prefix = String(cleaned.prefix(maximumLength))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix + "…"
    }

    private func reload() {
        guard let repository else { return }
        do {
            conversations = try repository.loadConversations().filter(\.hasMeaningfulContent)
            lastErrorDescription = nil
        } catch {
            conversations = []
            handle(error, userMessage: "Saved conversations could not be loaded.")
        }
    }

    private func migrateLegacyJSONIfNeeded(at legacyURL: URL) -> String? {
        guard let repository, fileManager.fileExists(atPath: legacyURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: legacyURL)
            let legacyConversations = try decoder.decode([Conversation].self, from: data)
            try repository.importConversations(legacyConversations)

            let importedIDs = Set(try repository.loadConversations().map(\.id))
            let expectedIDs = Set(legacyConversations.filter(\.hasMeaningfulContent).map(\.id))
            guard expectedIDs.isSubset(of: importedIDs) else {
                throw DatabaseError.transactionFailed("Legacy conversation verification failed.")
            }

            let backupURL = availableLegacyBackupURL(beside: legacyURL)
            try fileManager.moveItem(at: legacyURL, to: backupURL)
            #if DEBUG
            Self.logger.notice("Legacy JSON conversations imported and preserved as \(backupURL.lastPathComponent, privacy: .public)")
            #endif
            return nil
        } catch {
            Self.logger.error("Legacy conversation migration failed: \(error.localizedDescription, privacy: .public)")
            return "Existing conversations could not be migrated. The original JSON file was preserved."
        }
    }

    private func availableLegacyBackupURL(beside legacyURL: URL) -> URL {
        let preferred = legacyURL.deletingLastPathComponent().appendingPathComponent("conversations.migrated.json")
        guard fileManager.fileExists(atPath: preferred.path) else { return preferred }
        return legacyURL.deletingLastPathComponent()
            .appendingPathComponent("conversations.migrated-\(Int(Date().timeIntervalSince1970)).json")
    }

    private func handle(_ error: Error, userMessage: String) {
        lastErrorDescription = userMessage
        Self.logger.error("Conversation database operation failed: \(error.localizedDescription, privacy: .public)")
    }

    private static func cleanedTitle(_ source: String) -> String {
        source.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func defaultLegacyStorageURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport
            .appendingPathComponent("PersonalAI", isDirectory: true)
            .appendingPathComponent("conversations.json", isDirectory: false)
    }
}
