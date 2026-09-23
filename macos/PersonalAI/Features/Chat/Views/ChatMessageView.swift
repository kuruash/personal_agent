import SwiftUI

struct ChatMessageView: View {
    let message: ConversationMessage

    var body: some View {
        Group {
            if message.role == .user {
                userMessage
            } else {
                assistantMessage
            }
        }
        .textSelection(.enabled)
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 72)

            Text(message.content)
                .font(.body)
                .lineSpacing(3)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(AppColors.userMessageBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.subtleBorder, lineWidth: 1)
                }
                .frame(maxWidth: 560, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("You: \(message.content)")
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label("Personal AI", systemImage: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .labelStyle(PersonalAILabelStyle())

            MarkdownText(content: message.content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct PersonalAILabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: AppSpacing.xSmall) {
            configuration.icon
                .foregroundStyle(.tint)
            configuration.title
        }
    }
}

private struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            ForEach(Array(MarkdownBlock.parse(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(4)

        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(level == 1 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level == 1 ? AppSpacing.xSmall : 0)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(inlineMarkdown(item))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                        Text("\(item.number).")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(inlineMarkdown(item.text))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .code(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.medium)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppColors.subtleBorder, lineWidth: 1)
            }
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

private enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullets([String])
    case numbered([(number: Int, text: String)])
    case code(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if bulletText(from: line) != nil {
                var items: [String] = []
                while index < lines.count, let item = bulletText(from: lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bullets(items))
                continue
            }

            if numberedItem(from: line) != nil {
                var items: [(number: Int, text: String)] = []
                while index < lines.count, let item = numberedItem(from: lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty ||
                    candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") ||
                    heading(from: candidate) != nil ||
                    bulletText(from: candidate) != nil ||
                    numberedItem(from: candidate) != nil {
                    break
                }
                paragraphLines.append(candidate.trimmingCharacters(in: .whitespaces))
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let markerCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount),
              trimmed.dropFirst(markerCount).first == " " else { return nil }
        return (markerCount, String(trimmed.dropFirst(markerCount + 1)))
    }

    private static func bulletText(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return nil
    }

    private static func numberedItem(from line: String) -> (number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: "."),
              separator < trimmed.endIndex,
              trimmed.index(after: separator) < trimmed.endIndex,
              trimmed[trimmed.index(after: separator)] == " ",
              let number = Int(trimmed[..<separator]) else { return nil }
        return (number, String(trimmed[trimmed.index(separator, offsetBy: 2)...]))
    }
}
