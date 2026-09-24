import AppKit
import Foundation
import os

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: PersonalProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let store: ProfileStore
    private let documentAccess: ProfileDocumentAccess
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.personalai.app",
        category: "PersonalAI.ProfileDocuments"
    )

    init(store: ProfileStore, documentAccess: ProfileDocumentAccess = .shared) {
        self.store = store
        self.documentAccess = documentAccess
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try store.loadProfile()
            errorMessage = nil
        } catch {
            errorMessage = "Your profile could not be loaded. Please try again."
        }
    }

    @discardableResult
    func save(_ updated: PersonalProfile) -> Bool {
        do {
            try store.saveProfile(updated)
            profile = try store.loadProfile()
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Your changes could not be saved. They remain available to retry."
            return false
        }
    }

    func chooseDocument(id: String) {
        guard let updated = profile, let index = updated.documents.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose \(updated.documents[index].label)"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ProfileDocumentAccess.allowedContentTypes
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let documentType = updated.documents[index].type
                let association = try self.documentAccess.associate(url, with: id, documentType: documentType)
                let timestamp = ISO8601DateFormatter().string(from: Date())
                do {
                    try self.store.updateDocumentAssociation(
                        id: id,
                        filename: association.url.lastPathComponent,
                        path: association.url.path,
                        lastUpdated: timestamp
                    )
                } catch {
                    self.documentAccess.rollback(association, for: id)
                    self.logFailure(documentType: documentType, stage: error is ProfileRepository.DocumentAssociationError ? "document_record_lookup" : "repository_update")
                    self.errorMessage = "The selected document could not be associated."
                    return
                }
                do {
                    self.profile = try self.store.loadProfile()
                    self.errorMessage = nil
                    self.logSuccess(documentType: documentType)
                } catch {
                    self.logFailure(documentType: documentType, stage: "profile_refresh")
                    self.errorMessage = "The document was saved, but your profile could not be refreshed."
                }
            } catch let error as ProfileDocumentAccessError {
                self.logFailure(documentType: updated.documents[index].type, stage: Self.stage(for: error))
                self.errorMessage = "The selected document could not be associated."
            } catch {
                self.logFailure(documentType: updated.documents[index].type, stage: "unexpected")
                self.errorMessage = "The selected document could not be associated."
            }
        }
    }

    func removeDocument(id: String) {
        guard let updated = profile, let index = updated.documents.firstIndex(where: { $0.id == id }) else { return }
        let documentType = updated.documents[index].type
        do {
            try store.updateDocumentAssociation(id: id, filename: nil, path: nil, lastUpdated: nil)
            profile = try store.loadProfile()
            documentAccess.removeAssociation(for: id)
            errorMessage = nil
        } catch {
            logFailure(documentType: documentType, stage: error is ProfileRepository.DocumentAssociationError ? "document_record_lookup" : "repository_update")
            errorMessage = "The document association could not be removed."
        }
    }

    private static func stage(for error: ProfileDocumentAccessError) -> String {
        switch error {
        case .selectionInvalid: "selection_validation"
        case .unsupportedFileType: "file_type_validation"
        case .securityScopeFailed: "security_scope"
        case .bookmarkCreationFailed: "bookmark_creation"
        case .bookmarkPersistenceFailed: "bookmark_persistence"
        }
    }

    private func logFailure(documentType: String, stage: String) {
        #if DEBUG
        Self.logger.error("Profile document operation failed documentType=\(documentType, privacy: .public) operation=associate stage=\(stage, privacy: .public) success=false")
        #endif
    }

    private func logSuccess(documentType: String) {
        #if DEBUG
        Self.logger.notice("Profile document operation documentType=\(documentType, privacy: .public) operation=associate stage=profile_refresh success=true")
        #endif
    }
}
