import AppKit
import SwiftUI

struct ChatComposer: View {
    @Binding var text: String
    @Binding var attachments: [ChatAttachment]
    let isWorking: Bool
    let onSubmit: (String) -> Void
    @FocusState private var isFocused: Bool
    @State private var attachmentError: String?

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        VStack(spacing: AppSpacing.xSmall) {
            if !attachments.isEmpty {
                attachmentList
            }

            TextField("Ask Personal AI...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTypography.prompt)
                .lineLimit(1...7)
                .focused($isFocused)
                .onSubmit(submit)

            HStack {
                Button(action: chooseFile) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AppColors.subtleBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add File…")
                .accessibilityLabel("Add attachment")

                Spacer()

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canSubmit ? Color.white : Color.secondary)
                        .frame(width: 32, height: 32)
                        .background(canSubmit ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help("Send")
                .accessibilityLabel("Send message")
                .animation(.easeOut(duration: 0.12), value: canSubmit)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
        .background(AppColors.inputBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.primary.opacity(0.20) : AppColors.subtleBorder, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .alert("Attachment", isPresented: attachmentErrorBinding) {
            Button("OK") { attachmentError = nil }
        } message: {
            Text(attachmentError ?? "The selected file could not be attached.")
        }
    }

    private var attachmentList: some View {
        VStack(spacing: AppSpacing.xSmall) {
            ForEach(attachments) { attachment in
                HStack(spacing: AppSpacing.small) {
                    Image(systemName: attachment.systemImageName)
                        .foregroundStyle(.secondary)

                    Text(attachment.displayName)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("Staged only")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: AppSpacing.xSmall)

                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove attachment")
                    .accessibilityLabel("Remove \(attachment.displayName)")
                }
                .padding(.leading, AppSpacing.small)
                .padding(.trailing, AppSpacing.xSmall)
                .padding(.vertical, AppSpacing.xSmall)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var attachmentErrorBinding: Binding<Bool> {
        Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Add File"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                attachments.append(try ChatAttachmentAccess.makeAttachment(from: url))
                attachmentError = nil
            } catch let error as ChatAttachmentError {
                attachmentError = error.localizedDescription
            } catch {
                attachmentError = "The selected file could not be attached."
            }
            isFocused = true
        }
    }

    private func submit() {
        let submittedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty, !isWorking else { return }
        text = ""
        onSubmit(submittedText)
        isFocused = true
    }
}
