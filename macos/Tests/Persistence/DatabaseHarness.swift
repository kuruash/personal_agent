import Foundation

private enum TestFailure: Error { case failed(String) }
private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw TestFailure.failed(message) }
}

@main
@MainActor
private struct DatabaseHarness {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("PersonalAI-DatabaseTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("personal_ai.sqlite")
        let legacyURL = directory.appendingPathComponent("conversations.json")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        let database = try DatabaseManager(databaseURL: databaseURL)

        let version = try database.read { try $0.query("PRAGMA user_version;").first?.integer("user_version") }
        try require(version == 3, "Fresh database did not migrate through V3")
        let tables = try database.read {
            try $0.query("SELECT name FROM sqlite_master WHERE type = 'table';").compactMap { $0.text("name") }
        }
        for table in [
            "profile", "profile_links", "documents", "conversations", "messages", "agent_messages", "memories",
            "profile_identity", "profile_contact", "profile_address", "profile_education",
            "profile_experience", "profile_skills", "profile_projects", "profile_certifications",
            "profile_career_preferences", "profile_work_authorization", "profile_application_answers"
        ] {
            try require(tables.contains(table), "Missing table \(table)")
        }
        let foreignKeys = try database.read { try $0.query("PRAGMA foreign_keys;").first?.integer("foreign_keys") }
        try require(foreignKeys == 1, "Foreign keys were not enabled")
        print("PASS initialization: V3 schema and foreign keys enabled")

        let profileRepository = ProfileRepository(database: database)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000.125)
        let profile = UserProfile(
            fullName: "Test Person", preferredName: "Tester", location: nil,
            email: "test@example.invalid", phone: nil, createdAt: baseDate, updatedAt: baseDate
        )
        try profileRepository.saveProfile(profile)
        try require(try profileRepository.loadProfile() == profile, "Profile did not round-trip")
        var updatedProfile = profile
        updatedProfile.preferredName = "Updated"
        updatedProfile.updatedAt = baseDate.addingTimeInterval(5)
        try profileRepository.saveProfile(updatedProfile)
        try require(try profileRepository.loadProfile()?.preferredName == "Updated", "Profile update failed")
        do {
            try database.read {
                try $0.execute(
                    "INSERT INTO profile (id, created_at, updated_at) VALUES (?, ?, ?);",
                    bindings: [.integer(2), .text("test"), .text("test")]
                )
            }
            throw TestFailure.failed("Profile singleton constraint accepted id 2")
        } catch let error as TestFailure { throw error } catch { }
        print("PASS profile: save, load, update, and singleton constraint")

        let link = ProfileLink(id: "example_portfolio", label: "Portfolio", url: "https://example.invalid", createdAt: baseDate, updatedAt: baseDate)
        try profileRepository.saveLink(link)
        try require(try profileRepository.loadLinks() == [link], "Profile link did not round-trip")
        var updatedLink = link
        updatedLink.label = "Updated Portfolio"
        try profileRepository.saveLink(updatedLink)
        try require(try profileRepository.loadLinks().first?.label == "Updated Portfolio", "Profile link update failed")
        try profileRepository.deleteLink(id: link.id)
        try require(try profileRepository.loadLinks().isEmpty, "Profile link delete failed")
        print("PASS profile links: create, update, and delete")

        let documentRepository = DocumentRepository(database: database)
        let document = DocumentMetadata(
            id: "example_resume", type: "resume", name: "Test Resume", filePath: nil,
            mimeType: "text/plain", isPrimary: true, createdAt: baseDate, updatedAt: baseDate
        )
        try documentRepository.saveDocumentMetadata(document)
        try require(try documentRepository.getDocument(id: document.id) == document, "Document metadata did not round-trip")
        try require(try documentRepository.listDocuments().first?.isPrimary == true, "Document primary flag was lost")
        try documentRepository.deleteDocumentMetadata(id: document.id)
        try require(try documentRepository.listDocuments().isEmpty, "Document delete failed")
        print("PASS documents: metadata, primary flag, retrieval, and delete")

        let conversationRepository = ConversationRepository(database: database)
        let exactContent = "Ashish's \"Personal AI\"\n**Markdown**\nSELECT * FROM messages;\n😊"
        let conversationID = UUID()
        let userID = UUID()
        let assistantID = UUID()
        let toolCall = ToolCall(
            id: "call-1", type: "function",
            function: ToolCallFunction(name: "search_files", arguments: "{\"query\":\"README\"}")
        )
        let history = [
            ChatMessage(role: "user", content: exactContent),
            ChatMessage(role: "assistant", toolCalls: [toolCall]),
            ChatMessage(role: "tool", content: "{\"results\":[\"README.md\"]}", toolCallID: "call-1", name: "search_files"),
            ChatMessage(role: "assistant", content: "Found it.")
        ]
        let conversation = Conversation(
            id: conversationID, title: "Original", messages: [
                ConversationMessage(id: userID, role: .user, content: exactContent, createdAt: baseDate),
                ConversationMessage(id: assistantID, role: .assistant, content: "**Found it.**", createdAt: baseDate.addingTimeInterval(1))
            ], modelHistory: history, createdAt: baseDate, updatedAt: baseDate.addingTimeInterval(2)
        )
        try conversationRepository.save(conversation)
        let loaded = try conversationRepository.loadConversation(id: conversationID)
        try require(loaded?.messages.map(\.id) == [userID, assistantID], "Message IDs or order changed")
        try require(loaded?.messages.first?.content == exactContent, "Prepared-statement content changed")
        try require(loaded?.messages.last?.content == "**Found it.**", "Markdown changed")
        try require(loaded?.modelHistory == history, "Internal agent context changed")
        try conversationRepository.rename(id: conversationID, title: "Renamed")
        try require(try conversationRepository.loadConversation(id: conversationID)?.title == "Renamed", "Rename failed")

        let newer = Conversation(
            title: "Newer", messages: [ConversationMessage(role: .user, content: "New")],
            createdAt: baseDate, updatedAt: Date().addingTimeInterval(20)
        )
        try conversationRepository.save(newer)
        try require(try conversationRepository.loadConversations().first?.id == newer.id, "updatedAt ordering failed")
        print("PASS conversations/messages: order, Unicode, quotes, SQL text, Markdown, rename, and agent context")

        try conversationRepository.delete(id: conversationID)
        let remainingVisible = try database.read {
            try $0.query("SELECT id FROM messages WHERE conversation_id = ?;", bindings: [.text(conversationID.uuidString)])
        }
        let remainingAgent = try database.read {
            try $0.query("SELECT sequence FROM agent_messages WHERE conversation_id = ?;", bindings: [.text(conversationID.uuidString)])
        }
        try require(remainingVisible.isEmpty && remainingAgent.isEmpty, "Delete cascade left child records")
        print("PASS cascade: visible and internal messages deleted with conversation")

        database.close()
        let reopened = try DatabaseManager(databaseURL: databaseURL)
        let reopenedRepository = ConversationRepository(database: reopened)
        try require(try reopenedRepository.loadConversation(id: newer.id) != nil, "Data did not survive reopen")
        let reopenedVersion = try reopened.read { try $0.query("PRAGMA user_version;").first?.integer("user_version") }
        try require(reopenedVersion == 3, "Second migration changed schema version")
        try require(try reopenedRepository.loadConversations().count == 1, "Second migration duplicated data")
        print("PASS persistence/migrations: reopen retained data and migration remained idempotent")

        let legacyA = Conversation(
            id: UUID(), title: "Conversation A", messages: [
                ConversationMessage(id: UUID(), role: .user, content: "Hello", createdAt: baseDate),
                ConversationMessage(id: UUID(), role: .assistant, content: "**Markdown response**", createdAt: baseDate.addingTimeInterval(1))
            ], modelHistory: [ChatMessage(role: "user", content: "Hello"), ChatMessage(role: "assistant", content: "**Markdown response**")],
            createdAt: baseDate, updatedAt: baseDate.addingTimeInterval(1)
        )
        let legacyB = Conversation(
            id: UUID(), title: "Conversation B", messages: [
                ConversationMessage(id: UUID(), role: .user, content: "Turn one", createdAt: baseDate),
                ConversationMessage(id: UUID(), role: .assistant, content: "Answer one", createdAt: baseDate.addingTimeInterval(1)),
                ConversationMessage(id: UUID(), role: .user, content: "Turn two", createdAt: baseDate.addingTimeInterval(2))
            ], modelHistory: [ChatMessage(role: "user", content: "Turn one")],
            createdAt: baseDate, updatedAt: baseDate.addingTimeInterval(2)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyA, legacyB]).write(to: legacyURL, options: .atomic)
        let legacyStore = ConversationStore(database: reopened, legacyStorageURL: legacyURL, fileManager: fm)
        try require(legacyStore.conversation(id: legacyA.id)?.messages.last?.content == "**Markdown response**", "Legacy Markdown changed")
        try require(legacyStore.conversation(id: legacyB.id)?.messages.count == 3, "Legacy turns were lost")
        try require(!fm.fileExists(atPath: legacyURL.path), "Successful legacy file remained active")
        let backupURL = directory.appendingPathComponent("conversations.migrated.json")
        try require(fm.fileExists(atPath: backupURL.path), "Legacy backup was not preserved")

        try fm.copyItem(at: backupURL, to: legacyURL)
        let secondLegacyStore = ConversationStore(database: reopened, legacyStorageURL: legacyURL, fileManager: fm)
        let allIDs = secondLegacyStore.conversations.map(\.id)
        try require(Set(allIDs).count == allIDs.count, "Second legacy import duplicated conversations")
        try require(allIDs.filter { $0 == legacyA.id }.count == 1, "Legacy ID was not stable")
        print("PASS legacy migration: IDs, dates, messages, Markdown, and context preserved; second import idempotent")

        let stateDatabaseURL = directory.appendingPathComponent("conversation-state.sqlite")
        let stateDatabase = try DatabaseManager(databaseURL: stateDatabaseURL)
        let stateRepository = ConversationRepository(database: stateDatabase)
        let ten = Date(timeIntervalSince1970: 1_700_100_000)
        let eleven = ten.addingTimeInterval(3_600)
        let noon = eleven.addingTimeInterval(3_600)
        let chatA = Conversation(
            title: "Chat A",
            messages: [
                ConversationMessage(role: .user, content: "A1", createdAt: ten),
                ConversationMessage(role: .assistant, content: "A2", createdAt: ten.addingTimeInterval(1))
            ],
            createdAt: ten,
            updatedAt: ten
        )
        let chatB = Conversation(
            title: "Chat B",
            messages: [
                ConversationMessage(role: .user, content: "B1", createdAt: eleven),
                ConversationMessage(role: .assistant, content: "B2", createdAt: eleven.addingTimeInterval(1))
            ],
            createdAt: eleven,
            updatedAt: eleven
        )
        try stateRepository.save(chatA)
        try stateRepository.save(chatB)

        let stateStore = ConversationStore(
            database: stateDatabase,
            legacyStorageURL: directory.appendingPathComponent("missing-legacy.json"),
            fileManager: fm
        )
        let stateViewModel = AgentViewModel(conversationStore: stateStore)
        try require(stateStore.conversations.map(\.id) == [chatB.id, chatA.id], "Initial Recent ordering was incorrect")
        stateViewModel.selectConversation(id: chatA.id)
        try require(stateViewModel.currentConversationID == chatA.id, "Selecting Chat A did not synchronize its ID")
        try require(stateViewModel.messages.map(\.content) == ["A1", "A2"], "Selecting Chat A did not load only A messages")
        try require(stateStore.conversations.map(\.id) == [chatB.id, chatA.id], "Selection reordered Recent")
        try require(stateStore.conversation(id: chatA.id)?.updatedAt == ten, "Selection mutated updatedAt")

        stateViewModel.selectConversation(id: chatB.id)
        try require(stateViewModel.currentConversationID == chatB.id, "Selecting Chat B did not synchronize its ID")
        try require(stateViewModel.messages.map(\.content) == ["B1", "B2"], "A to B switch left stale or mixed messages")

        stateViewModel.submit("B3")
        let persistedB = try stateRepository.loadConversation(id: chatB.id)
        try require(persistedB?.messages.map(\.content) == ["B1", "B2", "B3"], "New selected-conversation message was persisted to the wrong conversation")
        try require(try stateRepository.loadConversation(id: chatA.id)?.messages.map(\.content) == ["A1", "A2"], "Sending to Chat B changed Chat A")
        stateViewModel.selectConversation(id: chatB.id)

        let restoredStore = ConversationStore(
            database: stateDatabase,
            legacyStorageURL: directory.appendingPathComponent("missing-restored-legacy.json"),
            fileManager: fm
        )
        let restoredViewModel = AgentViewModel(conversationStore: restoredStore)
        restoredViewModel.selectConversation(id: chatA.id)
        try require(restoredViewModel.messages.map(\.content) == ["A1", "A2"], "Fresh view-model did not restore Chat A from SQLite")
        restoredViewModel.selectConversation(id: chatB.id)
        try require(restoredViewModel.messages.map(\.content) == ["B1", "B2", "B3"], "Fresh view-model did not restore Chat B from SQLite")
        print("PASS conversation selection: isolated SQLite hydration, switching, selected send, and restoration")

        var changedA = chatA
        changedA.messages.append(ConversationMessage(role: .assistant, content: "Changed", createdAt: noon))
        changedA.updatedAt = Date().addingTimeInterval(60)
        try require(stateStore.save(changedA), "Meaningful Chat A update was not saved")
        try require(stateStore.conversations.map(\.id) == [chatA.id, chatB.id], "Content update did not reorder Recent")
        print("PASS conversation ordering: selection is read-only; content updates recency")

        stateViewModel.selectConversation(id: chatB.id)
        try require(stateViewModel.deleteConversation(id: chatA.id), "Non-selected delete failed")
        try require(stateViewModel.currentConversationID == chatB.id, "Non-selected delete changed selection")
        try require(stateStore.conversation(id: chatA.id) == nil, "Deleted non-selected conversation remained")
        try require(stateViewModel.deleteConversation(id: chatB.id), "Selected delete failed")
        try require(stateViewModel.currentConversationID == nil && stateViewModel.messages.isEmpty, "Selected delete left stale state")
        try require(stateStore.conversations.isEmpty, "Selected delete left a phantom Recent entry")
        let childRows = try stateDatabase.read {
            try $0.query("SELECT conversation_id FROM messages UNION ALL SELECT conversation_id FROM agent_messages;")
        }
        try require(childRows.isEmpty, "Conversation deletion left child records")

        stateViewModel.startNewConversation()
        try require(stateStore.conversations.isEmpty, "New Chat persisted an empty conversation")
        print("PASS chat state: deletes preserve/replace selection, cascade children, and New Chat stays transient")

        let attachmentURL = directory.appendingPathComponent("fictional-attachment.txt")
        try Data("harmless attachment fixture".utf8).write(to: attachmentURL)
        var attachments = [try ChatAttachmentAccess.makeAttachment(from: attachmentURL)]
        try require(attachments.first?.displayName == "fictional-attachment.txt", "Attachment display name was not retained")
        try require(attachments.first?.byteSize == 27, "Attachment size was not retained")
        attachments.removeAll()
        try require(fm.fileExists(atPath: attachmentURL.path), "Removing a draft attachment deleted the source file")
        do {
            _ = try ChatAttachmentAccess.makeAttachment(from: directory)
            throw TestFailure.failed("A directory was accepted as a file attachment")
        } catch ChatAttachmentError.invalidSelection { }
        print("PASS attachments: authorized file staging, metadata, safe removal, and invalid selection")

        print("ALL DATABASE TESTS PASSED")
    }
}
