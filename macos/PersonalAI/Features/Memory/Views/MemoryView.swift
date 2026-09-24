import SwiftUI

private struct MemoryEditorSession: Identifiable {
    let memory: MemoryRecord?
    var id: String { memory?.id.uuidString ?? "new-memory" }
}

struct MemoryView: View {
    @StateObject private var viewModel: MemoryViewModel
    @State private var editorSession: MemoryEditorSession?
    @State private var pendingDelete: MemoryRecord?

    init(store: MemoryStore) {
        _viewModel = StateObject(wrappedValue: MemoryViewModel(store: store))
    }

    var body: some View {
        DetailPage(
            title: "Memory",
            subtitle: "Information your Personal AI remembers across conversations. You control what is stored."
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                controls
                content
            }
        }
        .task { viewModel.load() }
        .onChange(of: viewModel.query) { _, _ in viewModel.load() }
        .onChange(of: viewModel.selectedType) { _, _ in viewModel.load() }
        .sheet(item: $editorSession) { session in
            MemoryEditorSheet(memory: session.memory) { content, type, importance in
                let saved: Bool
                if let memory = session.memory {
                    saved = viewModel.update(id: memory.id, content: content, type: type, importance: importance)
                } else {
                    saved = viewModel.create(content: content, type: type, importance: importance)
                }
                if saved { editorSession = nil }
            } onCancel: {
                editorSession = nil
            }
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: deleteBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { viewModel.delete(id: pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the selected memory from Personal AI.")
        }
        .alert("Memory", isPresented: errorBinding) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "The memory operation could not be completed.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack(spacing: AppSpacing.medium) {
                TextField("Search memories…", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Spacer()

                Button {
                    editorSession = MemoryEditorSession(memory: nil)
                } label: {
                    Label("Add Memory", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Picker("Memory type", selection: $viewModel.selectedType) {
                Text("All").tag(MemoryType?.none)
                ForEach(MemoryType.allCases) { type in
                    Text("\(type.displayName)s")
                        .tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading Memories…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.memories.isEmpty {
            VStack(spacing: AppSpacing.large) {
                EmptyStateView(
                    icon: "brain",
                    title: viewModel.query.isEmpty && viewModel.selectedType == nil ? "No memories yet" : "No matching memories",
                    description: viewModel.query.isEmpty && viewModel.selectedType == nil
                        ? "Add preferences, goals, projects, decisions, or useful context you want Personal AI to remember."
                        : "Try another search or memory type."
                )
                if viewModel.query.isEmpty && viewModel.selectedType == nil {
                    Button("Add Memory") { editorSession = MemoryEditorSession(memory: nil) }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.medium) {
                    ForEach(viewModel.memories) { memory in
                        MemoryCard(
                            memory: memory,
                            onEdit: { editorSession = MemoryEditorSession(memory: memory) },
                            onDelete: { pendingDelete = memory }
                        )
                    }
                }
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppSpacing.large)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

private struct MemoryCard: View {
    let memory: MemoryRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Label(memory.type.displayName, systemImage: icon)
                    .font(.headline)
                if memory.importance != .normal {
                    Text(memory.importance.displayName)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit", action: onEdit).buttonStyle(.borderless)
                Button("Delete", role: .destructive, action: onDelete).buttonStyle(.borderless)
            }
            Text(memory.content)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Updated \(memory.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(AppSpacing.large)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppColors.subtleBorder, lineWidth: 1) }
    }

    private var icon: String {
        switch memory.type {
        case .preference: "slider.horizontal.3"
        case .goal: "target"
        case .project: "hammer"
        case .decision: "checkmark.circle"
        case .context: "text.bubble"
        case .other: "brain"
        }
    }
}

private struct MemoryEditorSheet: View {
    let memory: MemoryRecord?
    @State private var content: String
    @State private var type: MemoryType
    @State private var importance: MemoryImportance
    let onSave: (String, MemoryType, MemoryImportance) -> Void
    let onCancel: () -> Void

    init(
        memory: MemoryRecord?,
        onSave: @escaping (String, MemoryType, MemoryImportance) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.memory = memory
        _content = State(initialValue: memory?.content ?? "")
        _type = State(initialValue: memory?.type ?? .context)
        _importance = State(initialValue: memory?.importance ?? .normal)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(memory == nil ? "Add Memory" : "Edit Memory")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(AppSpacing.large)

            Divider()

            Form {
                Picker("Type", selection: $type) {
                    ForEach(MemoryType.allCases) { type in Text(type.displayName).tag(type) }
                }
                Picker("Importance", selection: $importance) {
                    ForEach(MemoryImportance.allCases) { value in Text(value.displayName).tag(value) }
                }
                LabeledContent("Memory") {
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding(AppSpacing.xSmall)
                        .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).stroke(AppColors.subtleBorder) }
                }
            }
            .formStyle(.grouped)
            .padding(AppSpacing.large)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(memory == nil ? "Add" : "Save") {
                    onSave(content, type, importance)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 4_000)
            }
            .padding(AppSpacing.large)
        }
        .frame(width: 580, height: 430)
    }
}
