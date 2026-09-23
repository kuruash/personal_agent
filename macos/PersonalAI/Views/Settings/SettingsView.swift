import SwiftUI

struct SettingsView: View {
    @ObservedObject var agent: AgentViewModel
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var isFilesExpanded = false

    private let permissions = [
        PermissionItem(name: "Files", icon: "folder"),
        PermissionItem(name: "Terminal", icon: "terminal"),
        PermissionItem(name: "Browser", icon: "safari"),
        PermissionItem(name: "Git", icon: "point.3.connected.trianglepath.dotted"),
        PermissionItem(name: "Screen Access", icon: "rectangle.on.rectangle")
    ]

    var body: some View {
        DetailPage(title: "Settings", subtitle: "Configure Personal AI and its permissions.") {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    settingsSection("GENERAL") {
                        valueRow("App Name", value: "Personal AI")
                        Divider()
                        appearanceRow
                    }

                    settingsSection("PERMISSIONS") {
                        ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                            if permission.name == "Files" {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        isFilesExpanded.toggle()
                                    }
                                } label: {
                                    permissionRow(
                                        permission,
                                        status: filesStatus,
                                        isConfigured: !agent.approvedDirectories.isEmpty,
                                        showsDisclosure: true
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isFilesExpanded {
                                    Divider()
                                    filesConfiguration
                                }
                            } else {
                                permissionRow(permission, status: "Not configured")
                            }
                            if index < permissions.count - 1 { Divider() }
                        }
                    }

                    settingsSection("AI") {
                        valueRow("Model", value: agent.selectedModelID ?? "Not connected")
                        Divider()
                        valueRow("Provider", value: agent.providerName)
                    }
                }
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppSpacing.xLarge)
            }
        }
    }

    private var appearanceRow: some View {
        HStack(spacing: AppSpacing.large) {
            Text("Appearance")
            Spacer()
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
        .padding(.vertical, AppSpacing.small)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(AppTypography.sectionLabel)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xSmall)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, AppSpacing.medium)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.subtleBorder, lineWidth: 1)
            }
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppSpacing.medium)
    }

    private var filesStatus: String {
        let count = agent.approvedDirectories.count
        if count == 0 { return "Not configured" }
        return count == 1 ? "1 folder" : "\(count) folders"
    }

    private var filesConfiguration: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Personal AI currently has read-only access to folders you approve.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if agent.approvedDirectories.isEmpty {
                Text("No folders approved")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(agent.approvedDirectories.enumerated()), id: \.element.id) { index, directory in
                        HStack(spacing: AppSpacing.medium) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(directory.name)
                                Text(directory.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button("Remove", role: .destructive) {
                                agent.removeReadOnlyDirectory(directory)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, AppSpacing.small)

                        if index < agent.approvedDirectories.count - 1 { Divider() }
                    }
                }
            }

            Button(action: agent.chooseReadOnlyDirectory) {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, AppSpacing.medium)
    }

    private func permissionRow(
        _ permission: PermissionItem,
        status: String,
        isConfigured: Bool = false,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: permission.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(permission.name)
            Spacer()

            HStack(spacing: AppSpacing.xSmall) {
                Circle()
                    .fill(isConfigured ? Color.green : .secondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                Text(status)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if showsDisclosure {
                Image(systemName: isFilesExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, AppSpacing.small)
    }
}

private struct PermissionItem: Identifiable {
    let name: String
    let icon: String

    var id: String { name }
}
