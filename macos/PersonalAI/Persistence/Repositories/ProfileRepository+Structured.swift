import Foundation

extension ProfileRepository {
    enum DocumentAssociationError: Error {
        case documentRecordNotFound
    }

    func updateDocumentAssociation(id: String, filename: String?, path: String?, lastUpdated: String?, updatedAt: Date = Date()) throws {
        try database.read { connection in
            try connection.execute("""
                UPDATE documents
                SET filename = ?, file_path = ?, last_updated = ?, updated_at = ?
                WHERE id = ?;
                """, bindings: [
                    filename.sqliteValue, path.sqliteValue, lastUpdated.sqliteValue,
                    .text(RepositoryDate.encode(updatedAt)), .text(id)
                ])
            let changed = try connection.query("SELECT changes() AS count;").first?.integer("count") ?? 0
            guard changed == 1 else { throw DocumentAssociationError.documentRecordNotFound }
        }
    }

    /// Replaces the canonical structured profile in one transaction. This is the
    /// mutation path used by Profile UI; existing record IDs remain unchanged and
    /// records omitted from collection sections are deliberately deleted.
    func savePersonalProfile(_ profile: PersonalProfile, updatedAt: Date = Date()) throws {
        let timestamp = RepositoryDate.encode(updatedAt)
        try database.transaction { connection in
            try upsertSingletons(profile, timestamp: timestamp, connection: connection)
            if profile.address == nil {
                try connection.execute("DELETE FROM profile_address WHERE id = 1;")
            }
            try replaceCollection(table: "profile_links", ids: profile.links.map(\.id), connection: connection)
            try replaceCollection(table: "profile_education", ids: profile.education.map(\.id), connection: connection)
            try replaceCollection(table: "profile_experience", ids: profile.experience.map(\.id), connection: connection)
            try replaceCollection(table: "profile_projects", ids: profile.projects.map(\.id), connection: connection)
            try replaceCollection(table: "profile_certifications", ids: profile.certifications.map(\.id), connection: connection)
            try replaceCollection(table: "documents", ids: profile.documents.map(\.id), connection: connection)
            try connection.execute("DELETE FROM profile_skills;")
            try upsertLinks(profile.links, timestamp: timestamp, connection: connection)
            try upsertEducation(profile.education, timestamp: timestamp, connection: connection)
            try upsertExperience(profile.experience, timestamp: timestamp, connection: connection)
            try upsertSkills(profile.skills, timestamp: timestamp, connection: connection)
            try upsertProjects(profile.projects, timestamp: timestamp, connection: connection)
            try upsertCertifications(profile.certifications, timestamp: timestamp, connection: connection)
            try replaceDocuments(profile.documents, timestamp: timestamp, connection: connection)
        }
    }

    func importProfile(_ profile: PersonalProfile, importedAt: Date = Date()) throws {
        let timestamp = RepositoryDate.encode(importedAt)
        try database.transaction { connection in
            try upsertSingletons(profile, timestamp: timestamp, connection: connection)
            try upsertLinks(profile.links, timestamp: timestamp, connection: connection)
            try upsertEducation(profile.education, timestamp: timestamp, connection: connection)
            try upsertExperience(profile.experience, timestamp: timestamp, connection: connection)
            try upsertSkills(profile.skills, timestamp: timestamp, connection: connection)
            try upsertProjects(profile.projects, timestamp: timestamp, connection: connection)
            try upsertCertifications(profile.certifications, timestamp: timestamp, connection: connection)
            try upsertDocuments(profile.documents, timestamp: timestamp, connection: connection)
        }
    }

    func loadPersonalProfile() throws -> PersonalProfile? {
        try database.read { connection in
            guard let identityRow = try connection.query("SELECT * FROM profile_identity WHERE id = 1;").first,
                  let contactRow = try connection.query("SELECT * FROM profile_contact WHERE id = 1;").first,
                  let careerRow = try connection.query("SELECT * FROM profile_career_preferences WHERE id = 1;").first,
                  let workRow = try connection.query("SELECT * FROM profile_work_authorization WHERE id = 1;").first,
                  let answersRow = try connection.query("SELECT * FROM profile_application_answers WHERE id = 1;").first
            else { return nil }

            let addressRow = try connection.query("SELECT * FROM profile_address WHERE id = 1;").first
            return PersonalProfile(
                identity: ProfileIdentity(
                    fullName: try identityRow.requiredText("full_name"),
                    firstName: try identityRow.requiredText("first_name"),
                    lastName: try identityRow.requiredText("last_name"),
                    preferredName: try identityRow.requiredText("preferred_name"),
                    legalName: try identityRow.requiredText("legal_name")
                ),
                contact: ProfileContact(
                    primaryEmail: try contactRow.requiredText("primary_email"),
                    alternateEmail: contactRow.text("alternate_email"),
                    primaryPhone: try contactRow.requiredText("primary_phone")
                ),
                address: try addressRow.map { row in
                    ProfileAddress(
                        street: try row.requiredText("street"), city: try row.requiredText("city"),
                        state: try row.requiredText("state"), postalCode: try row.requiredText("postal_code"),
                        country: try row.requiredText("country")
                    )
                },
                links: try loadLinks(connection),
                education: try loadEducation(connection),
                experience: try loadExperience(connection),
                skills: try loadSkills(connection),
                projects: try loadProjects(connection),
                certifications: try loadCertifications(connection),
                careerPreferences: CareerPreferences(
                    targetRoles: try decodeStrings(careerRow.requiredText("target_roles_json")),
                    preferredLocations: try decodeStrings(careerRow.requiredText("preferred_locations_json")),
                    remote: careerRow.integer("remote") == 1,
                    hybrid: careerRow.integer("hybrid") == 1,
                    onsite: careerRow.integer("onsite") == 1,
                    willingToRelocate: careerRow.integer("willing_to_relocate") == 1,
                    preferredIndustries: try decodeStrings(careerRow.requiredText("preferred_industries_json")),
                    earliestStartDate: careerRow.text("earliest_start_date")
                ),
                workAuthorization: WorkAuthorization(
                    country: try workRow.requiredText("country"),
                    currentStatus: workRow.text("current_status"),
                    authorizationType: workRow.text("authorization_type"),
                    authorizationStartDate: workRow.text("authorization_start_date"),
                    authorizationExpirationDate: workRow.text("authorization_expiration_date"),
                    currentlyRequiredSponsorship: workRow.integer("currently_required_sponsorship") == 1,
                    futureRequiredSponsorship: workRow.integer("future_required_sponsorship") == 1,
                    futureSponsorshipType: workRow.text("future_sponsorship_type")
                ),
                applicationAnswers: ApplicationAnswers(
                    authorizedToWorkInUS: answersRow.integer("authorized_to_work_in_us") == 1,
                    requiresCurrentSponsorship: answersRow.integer("requires_current_sponsorship") == 1,
                    requiresFutureSponsorship: answersRow.integer("requires_future_sponsorship") == 1,
                    willingToRelocate: answersRow.integer("willing_to_relocate") == 1,
                    willingToWorkOnsite: answersRow.integer("willing_to_work_onsite") == 1,
                    willingToWorkHybrid: answersRow.integer("willing_to_work_hybrid") == 1,
                    willingToWorkRemote: answersRow.integer("willing_to_work_remote") == 1
                ),
                documents: try loadDocuments(connection)
            )
        }
    }

    private func upsertSingletons(_ profile: PersonalProfile, timestamp: String, connection: SQLiteConnection) throws {
        let i = profile.identity
        try connection.execute("""
            INSERT INTO profile_identity VALUES (1, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET full_name=excluded.full_name, first_name=excluded.first_name,
            last_name=excluded.last_name, preferred_name=excluded.preferred_name,
            legal_name=excluded.legal_name, updated_at=excluded.updated_at;
            """, bindings: [.text(i.fullName), .text(i.firstName), .text(i.lastName), .text(i.preferredName), .text(i.legalName), .text(timestamp)])
        let c = profile.contact
        try connection.execute("""
            INSERT INTO profile_contact VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET primary_email=excluded.primary_email,
            alternate_email=excluded.alternate_email, primary_phone=excluded.primary_phone, updated_at=excluded.updated_at;
            """, bindings: [.text(c.primaryEmail), c.alternateEmail.sqliteValue, .text(c.primaryPhone), .text(timestamp)])
        if let a = profile.address {
            try connection.execute("""
                INSERT INTO profile_address VALUES (1, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET street=excluded.street, city=excluded.city, state=excluded.state,
                postal_code=excluded.postal_code, country=excluded.country, updated_at=excluded.updated_at;
                """, bindings: [.text(a.street), .text(a.city), .text(a.state), .text(a.postalCode), .text(a.country), .text(timestamp)])
        }
        let cp = profile.careerPreferences
        try connection.execute("""
            INSERT INTO profile_career_preferences VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET target_roles_json=excluded.target_roles_json,
            preferred_locations_json=excluded.preferred_locations_json, remote=excluded.remote,
            hybrid=excluded.hybrid, onsite=excluded.onsite, willing_to_relocate=excluded.willing_to_relocate,
            preferred_industries_json=excluded.preferred_industries_json,
            earliest_start_date=excluded.earliest_start_date, updated_at=excluded.updated_at;
            """, bindings: [
                .text(try encodeStrings(cp.targetRoles)), .text(try encodeStrings(cp.preferredLocations)),
                .integer(cp.remote ? 1 : 0), .integer(cp.hybrid ? 1 : 0), .integer(cp.onsite ? 1 : 0),
                .integer(cp.willingToRelocate ? 1 : 0), .text(try encodeStrings(cp.preferredIndustries)),
                cp.earliestStartDate.sqliteValue, .text(timestamp)
            ])
        let wa = profile.workAuthorization
        try connection.execute("""
            INSERT INTO profile_work_authorization VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET country=excluded.country, current_status=excluded.current_status,
            authorization_type=excluded.authorization_type, authorization_start_date=excluded.authorization_start_date,
            authorization_expiration_date=excluded.authorization_expiration_date,
            currently_required_sponsorship=excluded.currently_required_sponsorship,
            future_required_sponsorship=excluded.future_required_sponsorship,
            future_sponsorship_type=excluded.future_sponsorship_type, updated_at=excluded.updated_at;
            """, bindings: [
                .text(wa.country), wa.currentStatus.sqliteValue, wa.authorizationType.sqliteValue,
                wa.authorizationStartDate.sqliteValue, wa.authorizationExpirationDate.sqliteValue,
                .integer(wa.currentlyRequiredSponsorship ? 1 : 0), .integer(wa.futureRequiredSponsorship ? 1 : 0),
                wa.futureSponsorshipType.sqliteValue, .text(timestamp)
            ])
        let aa = profile.applicationAnswers
        try connection.execute("""
            INSERT INTO profile_application_answers VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET authorized_to_work_in_us=excluded.authorized_to_work_in_us,
            requires_current_sponsorship=excluded.requires_current_sponsorship,
            requires_future_sponsorship=excluded.requires_future_sponsorship,
            willing_to_relocate=excluded.willing_to_relocate, willing_to_work_onsite=excluded.willing_to_work_onsite,
            willing_to_work_hybrid=excluded.willing_to_work_hybrid,
            willing_to_work_remote=excluded.willing_to_work_remote, updated_at=excluded.updated_at;
            """, bindings: [
                .integer(aa.authorizedToWorkInUS ? 1 : 0), .integer(aa.requiresCurrentSponsorship ? 1 : 0),
                .integer(aa.requiresFutureSponsorship ? 1 : 0), .integer(aa.willingToRelocate ? 1 : 0),
                .integer(aa.willingToWorkOnsite ? 1 : 0), .integer(aa.willingToWorkHybrid ? 1 : 0),
                .integer(aa.willingToWorkRemote ? 1 : 0), .text(timestamp)
            ])
    }

    private func upsertLinks(_ records: [ProfileLinkRecord], timestamp: String, connection: SQLiteConnection) throws {
        for record in records {
            try connection.execute("""
                INSERT INTO profile_links (id, label, url, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET label=excluded.label, url=excluded.url, updated_at=excluded.updated_at;
                """, bindings: [.text(record.id), .text(record.label), .text(record.url), .text(timestamp), .text(timestamp)])
        }
    }

    private func upsertEducation(_ records: [EducationRecord], timestamp: String, connection: SQLiteConnection) throws {
        for r in records {
            try connection.execute("""
                INSERT INTO profile_education VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET institution=excluded.institution, degree=excluded.degree, major=excluded.major,
                start_date=excluded.start_date, graduation_date=excluded.graduation_date, gpa=excluded.gpa,
                coursework_json=excluded.coursework_json, activities_json=excluded.activities_json,
                achievements_json=excluded.achievements_json, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(r.id), .text(r.institution), .text(r.degree), .text(r.major), .text(r.startDate),
                    .text(r.graduationDate), r.gpa.map(SQLiteValue.double) ?? .null,
                    .text(try encodeStrings(r.coursework)), .text(try encodeStrings(r.activities)),
                    .text(try encodeStrings(r.achievements)), .text(timestamp)
                ])
        }
    }

    private func upsertExperience(_ records: [ExperienceRecord], timestamp: String, connection: SQLiteConnection) throws {
        for r in records {
            try connection.execute("""
                INSERT INTO profile_experience VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET company=excluded.company, title=excluded.title,
                employment_type=excluded.employment_type, location=excluded.location, start_date=excluded.start_date,
                end_date=excluded.end_date, is_current=excluded.is_current, achievements_json=excluded.achievements_json,
                technologies_json=excluded.technologies_json, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(r.id), .text(r.company), .text(r.title), .text(r.employmentType), .text(r.location),
                    .text(r.startDate), r.endDate.sqliteValue, .integer(r.isCurrent ? 1 : 0),
                    .text(try encodeStrings(r.achievements)), .text(try encodeStrings(r.technologies)), .text(timestamp)
                ])
        }
    }

    private func upsertSkills(_ categories: [SkillCategory], timestamp: String, connection: SQLiteConnection) throws {
        for (categoryPosition, category) in categories.enumerated() {
            for (position, skill) in category.skills.enumerated() {
                try connection.execute("""
                    INSERT INTO profile_skills VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(category, skill) DO UPDATE SET category_position=excluded.category_position,
                    position=excluded.position, updated_at=excluded.updated_at;
                    """, bindings: [
                        .text(category.category), .text(skill), .integer(Int64(categoryPosition)),
                        .integer(Int64(position)), .text(timestamp)
                    ])
            }
        }
    }

    private func upsertProjects(_ records: [ProjectRecord], timestamp: String, connection: SQLiteConnection) throws {
        for (position, r) in records.enumerated() {
            try connection.execute("""
                INSERT INTO profile_projects VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, technologies_json=excluded.technologies_json,
                repository_url=excluded.repository_url, description=excluded.description,
                highlights_json=excluded.highlights_json, position=excluded.position, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(r.id), .text(r.name), .text(try encodeStrings(r.technologies)), r.repositoryURL.sqliteValue,
                    r.description.sqliteValue, .text(try encodeStrings(r.highlights)), .integer(Int64(position)), .text(timestamp)
                ])
        }
    }

    private func upsertCertifications(_ records: [CertificationRecord], timestamp: String, connection: SQLiteConnection) throws {
        for r in records {
            try connection.execute("""
                INSERT INTO profile_certifications VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name=excluded.name, issuer=excluded.issuer, type=excluded.type,
                issue_date=excluded.issue_date, expiration_date=excluded.expiration_date,
                credential_id=excluded.credential_id, credential_url=excluded.credential_url,
                unresolved=excluded.unresolved, updated_at=excluded.updated_at;
                """, bindings: [
                    .text(r.id), r.name.sqliteValue, r.issuer.sqliteValue, r.type.sqliteValue,
                    r.issueDate.sqliteValue, r.expirationDate.sqliteValue, r.credentialID.sqliteValue,
                    r.credentialURL.sqliteValue, .integer(r.unresolved ? 1 : 0), .text(timestamp)
                ])
        }
    }

    private func upsertDocuments(_ records: [ProfileDocument], timestamp: String, connection: SQLiteConnection) throws {
        for r in records {
            try connection.execute("""
                INSERT INTO documents (id, type, name, file_path, mime_type, is_primary, created_at, updated_at, label, filename, last_updated)
                VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET type=excluded.type, name=excluded.name,
                file_path=COALESCE(excluded.file_path, documents.file_path), is_primary=excluded.is_primary,
                updated_at=excluded.updated_at, label=excluded.label,
                filename=COALESCE(excluded.filename, documents.filename),
                last_updated=COALESCE(excluded.last_updated, documents.last_updated);
                """, bindings: [
                    .text(r.id), .text(r.type), .text(r.label), r.path.sqliteValue,
                    .integer(r.preferred ? 1 : 0), .text(timestamp), .text(timestamp), .text(r.label),
                    r.filename.sqliteValue, r.lastUpdated.sqliteValue
                ])
        }
    }

    private func replaceDocuments(_ records: [ProfileDocument], timestamp: String, connection: SQLiteConnection) throws {
        for r in records {
            try connection.execute("""
                INSERT INTO documents (id, type, name, file_path, mime_type, is_primary, created_at, updated_at, label, filename, last_updated)
                VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET type=excluded.type, name=excluded.name,
                file_path=excluded.file_path, is_primary=excluded.is_primary,
                updated_at=excluded.updated_at, label=excluded.label,
                filename=excluded.filename, last_updated=excluded.last_updated;
                """, bindings: [
                    .text(r.id), .text(r.type), .text(r.label), r.path.sqliteValue,
                    .integer(r.preferred ? 1 : 0), .text(timestamp), .text(timestamp), .text(r.label),
                    r.filename.sqliteValue, r.lastUpdated.sqliteValue
                ])
        }
    }

    private func loadLinks(_ connection: SQLiteConnection) throws -> [ProfileLinkRecord] {
        try connection.query("SELECT id, label, url FROM profile_links ORDER BY label COLLATE NOCASE, id;").map {
            ProfileLinkRecord(id: try $0.requiredText("id"), label: try $0.requiredText("label"), url: try $0.requiredText("url"))
        }
    }

    private func loadEducation(_ connection: SQLiteConnection) throws -> [EducationRecord] {
        try connection.query("SELECT * FROM profile_education ORDER BY start_date DESC, id;").map { r in
            EducationRecord(id: try r.requiredText("id"), institution: try r.requiredText("institution"),
                degree: try r.requiredText("degree"), major: try r.requiredText("major"),
                startDate: try r.requiredText("start_date"), graduationDate: try r.requiredText("graduation_date"),
                gpa: r.double("gpa"), coursework: try decodeStrings(r.requiredText("coursework_json")),
                activities: try decodeStrings(r.requiredText("activities_json")),
                achievements: try decodeStrings(r.requiredText("achievements_json")))
        }
    }

    private func loadExperience(_ connection: SQLiteConnection) throws -> [ExperienceRecord] {
        try connection.query("SELECT * FROM profile_experience ORDER BY start_date DESC, id;").map { r in
            ExperienceRecord(id: try r.requiredText("id"), company: try r.requiredText("company"),
                title: try r.requiredText("title"), employmentType: try r.requiredText("employment_type"),
                location: try r.requiredText("location"), startDate: try r.requiredText("start_date"),
                endDate: r.text("end_date"), isCurrent: r.integer("is_current") == 1,
                achievements: try decodeStrings(r.requiredText("achievements_json")),
                technologies: try decodeStrings(r.requiredText("technologies_json")))
        }
    }

    private func loadSkills(_ connection: SQLiteConnection) throws -> [SkillCategory] {
        let rows = try connection.query("SELECT category, skill FROM profile_skills ORDER BY category_position, position, skill;")
        let grouped = Dictionary(grouping: rows, by: { $0.text("category") ?? "" })
        var seen = Set<String>()
        let categories = rows.compactMap { $0.text("category") }.filter { seen.insert($0).inserted }
        return try categories.map { category in
            SkillCategory(category: category, skills: try grouped[category, default: []].map { try $0.requiredText("skill") })
        }
    }

    private func loadProjects(_ connection: SQLiteConnection) throws -> [ProjectRecord] {
        try connection.query("SELECT * FROM profile_projects ORDER BY position, id;").map { r in
            ProjectRecord(id: try r.requiredText("id"), name: try r.requiredText("name"),
                technologies: try decodeStrings(r.requiredText("technologies_json")),
                repositoryURL: r.text("repository_url"), description: r.text("description"),
                highlights: try decodeStrings(r.requiredText("highlights_json")))
        }
    }

    private func loadCertifications(_ connection: SQLiteConnection) throws -> [CertificationRecord] {
        try connection.query("SELECT * FROM profile_certifications ORDER BY COALESCE(name, id) COLLATE NOCASE, id;").map { r in
            CertificationRecord(id: try r.requiredText("id"), name: r.text("name"), issuer: r.text("issuer"),
                type: r.text("type"), issueDate: r.text("issue_date"), expirationDate: r.text("expiration_date"),
                credentialID: r.text("credential_id"), credentialURL: r.text("credential_url"),
                unresolved: r.integer("unresolved") == 1)
        }
    }

    private func loadDocuments(_ connection: SQLiteConnection) throws -> [ProfileDocument] {
        try connection.query("SELECT * FROM documents ORDER BY is_primary DESC, name COLLATE NOCASE, id;").map { r in
            let label = try r.text("label") ?? r.requiredText("name")
            return ProfileDocument(id: try r.requiredText("id"), type: try r.requiredText("type"),
                label: label, filename: r.text("filename"),
                path: r.text("file_path"), preferred: r.integer("is_primary") == 1,
                lastUpdated: r.text("last_updated"))
        }
    }

    private func encodeStrings(_ value: [String]) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw DatabaseError.decodingFailed("Could not encode profile list.") }
        return text
    }

    private func decodeStrings(_ value: String) throws -> [String] {
        do { return try JSONDecoder().decode([String].self, from: Data(value.utf8)) }
        catch { throw DatabaseError.decodingFailed("Could not decode profile list.") }
    }

    private func replaceCollection(table: String, ids: [String], connection: SQLiteConnection) throws {
        let allowed = ["profile_links", "profile_education", "profile_experience", "profile_projects", "profile_certifications", "documents"]
        guard allowed.contains(table) else { throw DatabaseError.transactionFailed("Unsupported profile collection.") }
        if ids.isEmpty {
            try connection.execute("DELETE FROM \(table);")
            return
        }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        try connection.execute(
            "DELETE FROM \(table) WHERE id NOT IN (\(placeholders));",
            bindings: ids.map(SQLiteValue.text)
        )
    }
}
