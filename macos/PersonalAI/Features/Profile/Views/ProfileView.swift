import SwiftUI

private enum ProfileEditTarget: Identifiable, Hashable {
    case identity, contact, address, skills, career, workAuthorization, applicationAnswers
    case link(String), education(String), experience(String), project(String), certification(String)

    var id: String {
        switch self {
        case .identity: "identity"
        case .contact: "contact"
        case .address: "address"
        case .skills: "skills"
        case .career: "career"
        case .workAuthorization: "workAuthorization"
        case .applicationAnswers: "applicationAnswers"
        case .link(let id): "link-\(id)"
        case .education(let id): "education-\(id)"
        case .experience(let id): "experience-\(id)"
        case .project(let id): "project-\(id)"
        case .certification(let id): "certification-\(id)"
        }
    }

    var title: String {
        switch self {
        case .identity: "Identity"
        case .contact: "Contact"
        case .address: "Address"
        case .skills: "Skills"
        case .career: "Career Preferences"
        case .workAuthorization: "Work Authorization"
        case .applicationAnswers: "Application Answers"
        case .link: "Link"
        case .education: "Education"
        case .experience: "Experience"
        case .project: "Project"
        case .certification: "Certification"
        }
    }
}

private struct ProfileEditorSession: Identifiable {
    let target: ProfileEditTarget
    let profile: PersonalProfile
    let isAdding: Bool

    var id: String { "\(isAdding ? "add" : "edit")-\(target.id)" }
}

struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @State private var editorSession: ProfileEditorSession?
    @State private var pendingDelete: ProfileEditTarget?

    init(store: ProfileStore) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(store: store))
    }

    var body: some View {
        DetailPage(
            title: "Profile",
            subtitle: "Information Personal AI can use to assist you. You control and can edit this information."
        ) {
            content
        }
        .task { if viewModel.profile == nil { viewModel.load() } }
        .alert("Profile", isPresented: errorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Your profile is unavailable.")
        }
        .sheet(item: $editorSession) { session in
            ProfileEditorSheet(session: session) { updated in
                if viewModel.save(updated) { editorSession = nil }
            } onCancel: {
                editorSession = nil
            }
        }
        .confirmationDialog(
            "Delete this profile record?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Only the selected record will be removed.")
        }
    }

    @ViewBuilder private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading Profile…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let profile = viewModel.profile {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    group("PERSONAL") {
                        identity(profile)
                        contact(profile)
                        address(profile)
                        links(profile)
                    }
                    group("PROFESSIONAL") {
                        education(profile)
                        experience(profile)
                        skills(profile)
                        projects(profile)
                        certifications(profile)
                    }
                    group("CAREER") {
                        career(profile)
                        workAuthorization(profile)
                        applicationAnswers(profile)
                    }
                    group("DOCUMENTS") { documents(profile) }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppSpacing.xLarge)
            }
        } else {
            EmptyStateView(
                icon: "person.crop.circle.badge.questionmark",
                title: "No profile available",
                description: "Import or create Profile data before editing it here."
            )
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(title).font(AppTypography.sectionLabel).foregroundStyle(.secondary).padding(.leading, AppSpacing.xSmall)
            content()
        }
    }

    private func identity(_ profile: PersonalProfile) -> some View {
        ProfileSectionCard(title: "Identity", icon: "person.text.rectangle", edit: { begin(.identity, profile) }) {
            ProfileValueRow("Full name", profile.identity.fullName)
            ProfileValueRow("Preferred name", profile.identity.preferredName)
            ProfileValueRow("Legal name", profile.identity.legalName)
        }
    }

    private func contact(_ profile: PersonalProfile) -> some View {
        ProfileSectionCard(title: "Contact", icon: "envelope", edit: { begin(.contact, profile) }) {
            ProfileValueRow("Primary email", profile.contact.primaryEmail)
            ProfileValueRow("Alternate email", profile.contact.alternateEmail)
            ProfileValueRow("Phone", profile.contact.primaryPhone)
        }
    }

    private func address(_ profile: PersonalProfile) -> some View {
        ProfileSectionCard(title: "Address", icon: "mappin.and.ellipse", edit: { begin(.address, profile) }) {
            if let address = profile.address {
                ProfileValueRow("Street", address.street)
                ProfileValueRow("City", address.city)
                ProfileValueRow("State", address.state)
                ProfileValueRow("Postal code", address.postalCode)
                ProfileValueRow("Country", address.country)
            } else { ProfileEmptyValue() }
        }
    }

    private func links(_ profile: PersonalProfile) -> some View {
        collectionCard("Links", icon: "link", records: profile.links, profile: profile, target: { .link($0.id) }) { record in
            VStack(alignment: .leading, spacing: 3) {
                Text(record.label).font(.headline)
                Text(record.url).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        } add: { p in
            let id = stableID("link")
            var copy = p; copy.links.append(ProfileLinkRecord(id: id, label: "", url: ""))
            beginAdd(.link(id), copy)
        }
    }

    private func education(_ profile: PersonalProfile) -> some View {
        collectionCard("Education", icon: "graduationcap", records: profile.education, profile: profile, target: { .education($0.id) }) { record in
            recordSummary(record.institution, "\(record.degree) · \(record.major)", formatDate(record.graduationDate))
        } add: { p in
            let id = stableID("education"); var copy = p
            copy.education.append(EducationRecord(id: id, institution: "", degree: "", major: "", startDate: "", graduationDate: "", gpa: nil, coursework: [], activities: [], achievements: []))
            beginAdd(.education(id), copy)
        }
    }

    private func experience(_ profile: PersonalProfile) -> some View {
        collectionCard("Experience", icon: "briefcase", records: profile.experience, profile: profile, target: { .experience($0.id) }) { record in
            recordSummary(record.company, record.title, "\(formatDate(record.startDate)) – \(record.isCurrent ? "Present" : formatDate(record.endDate))")
        } add: { p in
            let id = stableID("experience"); var copy = p
            copy.experience.append(ExperienceRecord(id: id, company: "", title: "", employmentType: "", location: "", startDate: "", endDate: nil, isCurrent: false, achievements: [], technologies: []))
            beginAdd(.experience(id), copy)
        }
    }

    private func skills(_ profile: PersonalProfile) -> some View {
        ProfileSectionCard(title: "Skills", icon: "hammer", edit: { begin(.skills, profile) }) {
            if profile.skills.isEmpty { ProfileEmptyValue() }
            ForEach(Array(profile.skills.enumerated()), id: \.offset) { _, category in
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(category.category).font(.subheadline.weight(.medium))
                    Text(category.skills.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                }.padding(.vertical, AppSpacing.xSmall)
            }
        }
    }

    private func projects(_ profile: PersonalProfile) -> some View {
        collectionCard("Projects", icon: "shippingbox", records: profile.projects, profile: profile, target: { .project($0.id) }) { record in
            recordSummary(record.name, record.technologies.joined(separator: " · "), record.description)
        } add: { p in
            let id = stableID("project"); var copy = p
            copy.projects.append(ProjectRecord(id: id, name: "", technologies: [], repositoryURL: nil, description: nil, highlights: []))
            beginAdd(.project(id), copy)
        }
    }

    private func certifications(_ profile: PersonalProfile) -> some View {
        collectionCard("Certifications", icon: "checkmark.seal", records: profile.certifications, profile: profile, target: { .certification($0.id) }) { record in
            recordSummary(provided(record.name), provided(record.issuer), record.expirationDate.map { "Expires \(formatDate($0))" })
        } add: { p in
            let id = stableID("certification"); var copy = p
            copy.certifications.append(CertificationRecord(id: id, name: nil, issuer: nil, type: nil, issueDate: nil, expirationDate: nil, credentialID: nil, credentialURL: nil, unresolved: false))
            beginAdd(.certification(id), copy)
        }
    }

    private func career(_ profile: PersonalProfile) -> some View {
        let value = profile.careerPreferences
        return ProfileSectionCard(title: "Career Preferences", icon: "target", edit: { begin(.career, profile) }) {
            ProfileValueRow("Target roles", value.targetRoles.joined(separator: ", "))
            ProfileValueRow("Preferred locations", value.preferredLocations.joined(separator: ", "))
            ProfileValueRow("Work environment", [value.remote ? "Remote" : nil, value.hybrid ? "Hybrid" : nil, value.onsite ? "Onsite" : nil].compactMap { $0 }.joined(separator: ", "))
            ProfileValueRow("Willing to relocate", yesNo(value.willingToRelocate))
            ProfileValueRow("Earliest start", value.earliestStartDate.map(formatDate))
        }
    }

    private func workAuthorization(_ profile: PersonalProfile) -> some View {
        let value = profile.workAuthorization
        return ProfileSectionCard(title: "Work Authorization", icon: "person.badge.key", edit: { begin(.workAuthorization, profile) }) {
            ProfileValueRow("Country", value.country)
            ProfileValueRow("Current status", value.currentStatus)
            ProfileValueRow("Authorization type", value.authorizationType)
            ProfileValueRow("Authorization start", value.authorizationStartDate.map(formatDate))
            ProfileValueRow("Authorization expiration", value.authorizationExpirationDate.map(formatDate))
            ProfileValueRow("Requires sponsorship now", yesNo(value.currentlyRequiredSponsorship))
            ProfileValueRow("Requires future sponsorship", yesNo(value.futureRequiredSponsorship))
            ProfileValueRow("Future sponsorship type", value.futureSponsorshipType)
        }
    }

    private func applicationAnswers(_ profile: PersonalProfile) -> some View {
        let value = profile.applicationAnswers
        return ProfileSectionCard(title: "Application Answers", icon: "list.clipboard", edit: { begin(.applicationAnswers, profile) }) {
            ProfileValueRow("Authorized to work in US", yesNo(value.authorizedToWorkInUS))
            ProfileValueRow("Requires current sponsorship", yesNo(value.requiresCurrentSponsorship))
            ProfileValueRow("Requires future sponsorship", yesNo(value.requiresFutureSponsorship))
            ProfileValueRow("Willing to relocate", yesNo(value.willingToRelocate))
            ProfileValueRow("Open to onsite", yesNo(value.willingToWorkOnsite))
            ProfileValueRow("Open to hybrid", yesNo(value.willingToWorkHybrid))
            ProfileValueRow("Open to remote", yesNo(value.willingToWorkRemote))
        }
    }

    private func documents(_ profile: PersonalProfile) -> some View {
        ProfileSectionCard(title: "Documents", icon: "doc.text", edit: nil) {
            if profile.documents.isEmpty { ProfileEmptyValue() }
            ForEach(profile.documents) { document in
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: document.type == "resume" ? "doc.text" : "doc")
                        .foregroundStyle(.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.label).font(.headline)
                        Text(document.filename ?? "No file selected").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(document.filename == nil ? "Choose File" : "Replace") { viewModel.chooseDocument(id: document.id) }
                    if document.filename != nil {
                        Button("Remove", role: .destructive) { viewModel.removeDocument(id: document.id) }
                    }
                }.padding(.vertical, AppSpacing.small)
            }
        }
    }

    private func collectionCard<Record: Identifiable, Row: View>(
        _ title: String, icon: String, records: [Record], profile: PersonalProfile,
        target: @escaping (Record) -> ProfileEditTarget,
        @ViewBuilder row: @escaping (Record) -> Row,
        add: @escaping (PersonalProfile) -> Void
    ) -> some View where Record.ID == String {
        ProfileSectionCard(title: title, icon: icon, edit: nil) {
            if records.isEmpty { ProfileEmptyValue() }
            ForEach(records) { record in
                HStack(alignment: .top, spacing: AppSpacing.medium) {
                    row(record)
                    Spacer()
                    Button("Edit") { begin(target(record), profile) }.buttonStyle(.borderless)
                    Button(role: .destructive) { pendingDelete = target(record) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Delete")
                }.padding(.vertical, AppSpacing.xSmall)
            }
            Button { add(profile) } label: { Label("Add \(title.dropLast(title.hasSuffix("s") ? 1 : 0))", systemImage: "plus") }
                .buttonStyle(.borderless).padding(.top, AppSpacing.xSmall)
        }
    }

    private func begin(_ target: ProfileEditTarget, _ profile: PersonalProfile) {
        editorSession = ProfileEditorSession(target: target, profile: profile, isAdding: false)
    }

    private func beginAdd(_ target: ProfileEditTarget, _ profile: PersonalProfile) {
        editorSession = ProfileEditorSession(target: target, profile: profile, isAdding: true)
    }

    private func confirmDelete() {
        guard let target = pendingDelete, var updated = viewModel.profile else { return }
        switch target {
        case .link(let id): updated.links.removeAll { $0.id == id }
        case .education(let id): updated.education.removeAll { $0.id == id }
        case .experience(let id): updated.experience.removeAll { $0.id == id }
        case .project(let id): updated.projects.removeAll { $0.id == id }
        case .certification(let id): updated.certifications.removeAll { $0.id == id }
        default: break
        }
        _ = viewModel.save(updated)
        pendingDelete = nil
    }

    private var errorBinding: Binding<Bool> { Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } }) }
    private var deleteDialogBinding: Binding<Bool> { Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }) }
    private func stableID(_ prefix: String) -> String { "\(prefix)_\(UUID().uuidString.lowercased())" }
}

private struct ProfileSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let edit: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Label(title, systemImage: icon).font(.title3.weight(.semibold))
                Spacer()
                if let edit { Button("Edit", action: edit).buttonStyle(.borderless) }
            }
            Divider()
            content
        }
        .padding(AppSpacing.large)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppColors.subtleBorder, lineWidth: 1) }
    }
}

private struct ProfileValueRow: View {
    let label: String
    let value: String?
    init(_ label: String, _ value: String?) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: AppSpacing.large)
            Text(provided(value)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.padding(.vertical, 2)
    }
}

private struct ProfileEmptyValue: View {
    var body: some View { Text("Not provided").font(.callout).foregroundStyle(.tertiary).padding(.vertical, AppSpacing.xSmall) }
}

private func recordSummary(_ title: String, _ subtitle: String?, _ detail: String?) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(provided(title)).font(.headline)
        if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(2) }
    }
}

private func provided(_ value: String?) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Not provided" }
    return value
}
private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
private func formatDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not provided" }
    let formats = ["yyyy-MM-dd", "yyyy-MM"]
    for format in formats {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = format
        if let date = parser.date(from: value) {
            let output = DateFormatter(); output.dateFormat = format == "yyyy-MM-dd" ? "MMM d, yyyy" : "MMM yyyy"
            return output.string(from: date)
        }
    }
    return value
}

private struct ProfileEditorSheet: View {
    let session: ProfileEditorSession
    @State var profile: PersonalProfile
    @State private var validationMessage: String?
    let onSave: (PersonalProfile) -> Void
    let onCancel: () -> Void

    init(session: ProfileEditorSession, onSave: @escaping (PersonalProfile) -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        _profile = State(initialValue: session.profile)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var target: ProfileEditTarget { session.target }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(session.isAdding ? "Add" : "Edit") \(target.title)")
                        .font(.title2.weight(.semibold))
                    Text(session.isAdding ? "Enter the details for this new profile record." : "Update the stored profile information below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
                .padding(AppSpacing.large)
            Divider()
            Form { editor }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, AppSpacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if let validationMessage {
                    Text(validationMessage).font(.callout).foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(session.isAdding ? "Add" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }.padding(AppSpacing.large)
        }
        .frame(width: 620, height: sheetHeight)
    }

    @ViewBuilder private var editor: some View {
        switch target {
        case .identity:
            TextField("Full name", text: $profile.identity.fullName)
            TextField("First name", text: $profile.identity.firstName)
            TextField("Last name", text: $profile.identity.lastName)
            TextField("Preferred name", text: $profile.identity.preferredName)
            TextField("Legal name", text: $profile.identity.legalName)
        case .contact:
            TextField("Primary email", text: $profile.contact.primaryEmail)
            TextField("Alternate email", text: optional($profile.contact.alternateEmail))
            TextField("Primary phone", text: $profile.contact.primaryPhone)
        case .address:
            addressEditor
        case .skills:
            skillsEditor
        case .career:
            listField("Target roles", binding: $profile.careerPreferences.targetRoles)
            listField("Preferred locations", binding: $profile.careerPreferences.preferredLocations)
            listField("Preferred industries", binding: $profile.careerPreferences.preferredIndustries)
            Toggle("Remote", isOn: $profile.careerPreferences.remote)
            Toggle("Hybrid", isOn: $profile.careerPreferences.hybrid)
            Toggle("Onsite", isOn: $profile.careerPreferences.onsite)
            Toggle("Willing to relocate", isOn: $profile.careerPreferences.willingToRelocate)
            TextField("Earliest start date (YYYY-MM-DD)", text: optional($profile.careerPreferences.earliestStartDate))
        case .workAuthorization:
            TextField("Country", text: $profile.workAuthorization.country)
            TextField("Current status", text: optional($profile.workAuthorization.currentStatus))
            TextField("Authorization type", text: optional($profile.workAuthorization.authorizationType))
            TextField("Authorization start (YYYY-MM-DD)", text: optional($profile.workAuthorization.authorizationStartDate))
            TextField("Authorization expiration (YYYY-MM-DD)", text: optional($profile.workAuthorization.authorizationExpirationDate))
            Toggle("Currently requires sponsorship", isOn: $profile.workAuthorization.currentlyRequiredSponsorship)
            Toggle("Will require sponsorship in the future", isOn: $profile.workAuthorization.futureRequiredSponsorship)
            TextField("Future sponsorship type", text: optional($profile.workAuthorization.futureSponsorshipType))
        case .applicationAnswers:
            Toggle("Authorized to work in US", isOn: $profile.applicationAnswers.authorizedToWorkInUS)
            Toggle("Requires current sponsorship", isOn: $profile.applicationAnswers.requiresCurrentSponsorship)
            Toggle("Requires future sponsorship", isOn: $profile.applicationAnswers.requiresFutureSponsorship)
            Toggle("Willing to relocate", isOn: $profile.applicationAnswers.willingToRelocate)
            Toggle("Open to onsite", isOn: $profile.applicationAnswers.willingToWorkOnsite)
            Toggle("Open to hybrid", isOn: $profile.applicationAnswers.willingToWorkHybrid)
            Toggle("Open to remote", isOn: $profile.applicationAnswers.willingToWorkRemote)
        case .link(let id): linkEditor(id)
        case .education(let id): educationEditor(id)
        case .experience(let id): experienceEditor(id)
        case .project(let id): projectEditor(id)
        case .certification(let id): certificationEditor(id)
        }
    }

    private var addressEditor: some View {
        Group {
            if profile.address == nil { Button("Add Address") { profile.address = ProfileAddress(street: "", city: "", state: "", postalCode: "", country: "") } }
            if profile.address != nil {
                TextField("Street", text: address(\.street))
                TextField("City", text: address(\.city))
                TextField("State", text: address(\.state))
                TextField("Postal code", text: address(\.postalCode))
                TextField("Country", text: address(\.country))
                Button("Remove Address", role: .destructive) { profile.address = nil }
            }
        }
    }

    private var skillsEditor: some View {
        Group {
            ForEach(profile.skills.indices, id: \.self) { index in
                Section {
                    TextField("Category", text: $profile.skills[index].category)
                    listField("Skills", binding: $profile.skills[index].skills)
                    Button("Remove Category", role: .destructive) { profile.skills.remove(at: index) }
                }
            }
            Button("Add Category") { profile.skills.append(SkillCategory(category: "", skills: [])) }
        }
    }

    @ViewBuilder private func linkEditor(_ id: String) -> some View {
        if let index = profile.links.firstIndex(where: { $0.id == id }) {
            TextField("Label", text: $profile.links[index].label)
            TextField("URL", text: $profile.links[index].url)
        }
    }

    @ViewBuilder private func educationEditor(_ id: String) -> some View {
        if let index = profile.education.firstIndex(where: { $0.id == id }) {
            TextField("Institution", text: $profile.education[index].institution)
            TextField("Degree", text: $profile.education[index].degree)
            TextField("Major", text: $profile.education[index].major)
            TextField("Start date", text: $profile.education[index].startDate)
            TextField("Graduation date", text: $profile.education[index].graduationDate)
            TextField("GPA", value: $profile.education[index].gpa, format: .number)
            listField("Coursework", binding: $profile.education[index].coursework)
            listField("Activities", binding: $profile.education[index].activities)
            listField("Achievements", binding: $profile.education[index].achievements)
        }
    }

    @ViewBuilder private func experienceEditor(_ id: String) -> some View {
        if let index = profile.experience.firstIndex(where: { $0.id == id }) {
            TextField("Company", text: $profile.experience[index].company)
            TextField("Title", text: $profile.experience[index].title)
            TextField("Employment type", text: $profile.experience[index].employmentType)
            TextField("Location", text: $profile.experience[index].location)
            TextField("Start date", text: $profile.experience[index].startDate)
            Toggle("Current role", isOn: $profile.experience[index].isCurrent)
            if !profile.experience[index].isCurrent { TextField("End date", text: optional($profile.experience[index].endDate)) }
            listField("Technologies", binding: $profile.experience[index].technologies)
            listField("Achievements", binding: $profile.experience[index].achievements)
        }
    }

    @ViewBuilder private func projectEditor(_ id: String) -> some View {
        if let index = profile.projects.firstIndex(where: { $0.id == id }) {
            TextField("Name", text: $profile.projects[index].name)
            TextField("Repository URL", text: optional($profile.projects[index].repositoryURL))
            TextField("Description", text: optional($profile.projects[index].description), axis: .vertical)
            listField("Technologies", binding: $profile.projects[index].technologies)
            listField("Highlights", binding: $profile.projects[index].highlights)
        }
    }

    @ViewBuilder private func certificationEditor(_ id: String) -> some View {
        if let index = profile.certifications.firstIndex(where: { $0.id == id }) {
            TextField("Name", text: optional($profile.certifications[index].name))
            TextField("Issuer", text: optional($profile.certifications[index].issuer))
            TextField("Type", text: optional($profile.certifications[index].type))
            TextField("Issue date", text: optional($profile.certifications[index].issueDate))
            TextField("Expiration date", text: optional($profile.certifications[index].expirationDate))
            TextField("Credential ID", text: optional($profile.certifications[index].credentialID))
            TextField("Credential URL", text: optional($profile.certifications[index].credentialURL))
            Toggle("Unresolved", isOn: $profile.certifications[index].unresolved)
        }
    }

    private func listField(_ label: String, binding: Binding<[String]>) -> some View {
        TextField(label, text: Binding(
            get: { binding.wrappedValue.joined(separator: ", ") },
            set: { binding.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        ), axis: .vertical)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func address(_ keyPath: WritableKeyPath<ProfileAddress, String>) -> Binding<String> {
        Binding(get: { profile.address?[keyPath: keyPath] ?? "" }, set: { profile.address?[keyPath: keyPath] = $0 })
    }

    private var sheetHeight: CGFloat {
        switch target {
        case .identity, .contact, .address, .link, .project: 520
        case .education, .experience, .certification: 650
        case .skills, .career, .workAuthorization, .applicationAnswers: 620
        }
    }

    private func save() {
        if let message = validationError {
            validationMessage = message
            return
        }
        validationMessage = nil
        onSave(profile)
    }

    private var validationError: String? {
        func empty(_ value: String?) -> Bool {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        switch target {
        case .identity:
            return [profile.identity.fullName, profile.identity.firstName, profile.identity.lastName,
                    profile.identity.preferredName, profile.identity.legalName].contains(where: empty)
                ? "Complete all required identity fields." : nil
        case .contact:
            return empty(profile.contact.primaryEmail) || empty(profile.contact.primaryPhone)
                ? "Primary email and phone are required." : nil
        case .link(let id):
            guard let value = profile.links.first(where: { $0.id == id }) else { return "The link is unavailable." }
            return empty(value.label) || empty(value.url) ? "Label and URL are required." : nil
        case .education(let id):
            guard let value = profile.education.first(where: { $0.id == id }) else { return "The education record is unavailable." }
            return empty(value.institution) || empty(value.degree) || empty(value.major) || empty(value.startDate) || empty(value.graduationDate)
                ? "Institution, degree, major, and dates are required." : nil
        case .experience(let id):
            guard let value = profile.experience.first(where: { $0.id == id }) else { return "The experience record is unavailable." }
            return empty(value.company) || empty(value.title) || empty(value.employmentType) || empty(value.location) || empty(value.startDate)
                ? "Company, title, employment type, location, and start date are required." : nil
        case .project(let id):
            guard let value = profile.projects.first(where: { $0.id == id }) else { return "The project is unavailable." }
            return empty(value.name) ? "Project name is required." : nil
        case .certification(let id):
            guard let value = profile.certifications.first(where: { $0.id == id }) else { return "The certification is unavailable." }
            return empty(value.name) ? "Certification name is required." : nil
        case .address:
            guard let value = profile.address else { return nil }
            return [value.street, value.city, value.state, value.postalCode, value.country].contains(where: empty)
                ? "Complete all address fields or remove the address." : nil
        case .skills:
            return profile.skills.contains { empty($0.category) || $0.skills.isEmpty }
                ? "Each skill category needs a name and at least one skill." : nil
        case .career, .workAuthorization, .applicationAnswers:
            return nil
        }
    }
}
