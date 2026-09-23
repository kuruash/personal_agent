import Foundation

final class ProfileRepository {
    let database: DatabaseManager

    init(database: DatabaseManager) { self.database = database }

    func loadProfile() throws -> UserProfile? {
        try database.read { connection in
            guard let row = try connection.query("SELECT * FROM profile WHERE id = 1;").first else { return nil }
            return UserProfile(
                fullName: row.text("full_name"), preferredName: row.text("preferred_name"),
                location: row.text("location"), email: row.text("email"), phone: row.text("phone"),
                createdAt: try RepositoryDate.decode(row.requiredText("created_at")),
                updatedAt: try RepositoryDate.decode(row.requiredText("updated_at"))
            )
        }
    }

    func saveProfile(_ profile: UserProfile) throws {
        try database.read { connection in
            try connection.execute("""
                INSERT INTO profile (id, full_name, preferred_name, location, email, phone, created_at, updated_at)
                VALUES (1, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET full_name=excluded.full_name,
                    preferred_name=excluded.preferred_name, location=excluded.location,
                    email=excluded.email, phone=excluded.phone, updated_at=excluded.updated_at;
                """, bindings: [
                    profile.fullName.sqliteValue, profile.preferredName.sqliteValue,
                    profile.location.sqliteValue, profile.email.sqliteValue, profile.phone.sqliteValue,
                    .text(RepositoryDate.encode(profile.createdAt)), .text(RepositoryDate.encode(profile.updatedAt))
                ])
        }
    }

    func loadLinks() throws -> [ProfileLink] {
        try database.read { connection in
            try connection.query("SELECT * FROM profile_links ORDER BY created_at ASC;").map { row in
                return ProfileLink(
                    id: try row.requiredText("id"), label: try row.requiredText("label"), url: try row.requiredText("url"),
                    createdAt: try RepositoryDate.decode(row.requiredText("created_at")),
                    updatedAt: try RepositoryDate.decode(row.requiredText("updated_at"))
                )
            }
        }
    }

    func saveLink(_ link: ProfileLink) throws {
        try database.read { connection in
            try connection.execute("""
                INSERT INTO profile_links (id, label, url, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET label=excluded.label, url=excluded.url, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(link.id), .text(link.label), .text(link.url),
                    .text(RepositoryDate.encode(link.createdAt)), .text(RepositoryDate.encode(link.updatedAt))
                ])
        }
    }

    func deleteLink(id: String) throws {
        try database.read { connection in
            try connection.execute("DELETE FROM profile_links WHERE id = ?;", bindings: [.text(id)])
        }
    }
}
