import SwiftUI

/// Model replies as readable blocks: headings, bullet and numbered lists, quotes, paragraphs –
/// with **bold**, *italic*, `code` and links inside. SwiftUI's own `Text(markdown)` only does the inline part.
struct FennMarkdown: View {
    let text: String
    var size: CGFloat = 14
    var color: Color = Fenn.fg.opacity(0.92)

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                view(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case numbered([(String, String)])
        case quote(String)
        case rule

        static func == (lhs: Block, rhs: Block) -> Bool {
            switch (lhs, rhs) {
            case let (.heading(a), .heading(b)), let (.paragraph(a), .paragraph(b)), let (.quote(a), .quote(b)): return a == b
            case let (.bullets(a), .bullets(b)): return a == b
            case let (.numbered(a), .numbered(b)): return a.map(\.0) == b.map(\.0) && a.map(\.1) == b.map(\.1)
            case (.rule, .rule): return true
            default: return false
            }
        }
    }

    @ViewBuilder
    private func view(_ block: Block) -> some View {
        switch block {
        case .heading(let line):
            inline(line).font(.fenn(size: size + 1, weight: .semibold)).foregroundStyle(Fenn.fg).padding(.top, 2)
        case .paragraph(let line):
            inline(line).font(.fenn(size: size)).lineSpacing(3).foregroundStyle(color)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: size * 0.45) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Fenn.accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + size * 0.28 }
                        inline(item).font(.fenn(size: size)).lineSpacing(3).foregroundStyle(color)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: size * 0.45) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.0).font(.fenn(size: size, weight: .semibold).monospacedDigit()).foregroundStyle(Fenn.accent)
                        inline(item.1).font(.fenn(size: size)).lineSpacing(3).foregroundStyle(color)
                    }
                }
            }
        case .quote(let line):
            inline(line).font(.fenn(size: size)).italic().lineSpacing(3).foregroundStyle(color.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 13)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1.5).fill(Fenn.accent.opacity(0.6)).frame(width: 3) }
        case .rule:
            Rectangle().fill(Fenn.hairline).frame(height: 1)
        }
    }

    private func inline(_ line: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: line, options: options) { return Text(attributed) }
        return Text(line)
    }

    /// Splits the reply into blocks. Continuation lines join their list item or paragraph.
    static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [(String, String)] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }

        for raw in text.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" || line == "___" {
                flush(); blocks.append(.rule)
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else if let item = bullet(line) {
                if !paragraph.isEmpty || !numbered.isEmpty { flush() }
                bullets.append(item)
            } else if let (number, item) = numberedItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty { flush() }
                numbered.append((number, item))
            } else if raw.hasPrefix("  ") || raw.hasPrefix("\t"), !bullets.isEmpty {
                bullets[bullets.count - 1] += " " + line
            } else if raw.hasPrefix("  ") || raw.hasPrefix("\t"), !numbered.isEmpty {
                numbered[numbered.count - 1].1 += " " + line
            } else {
                if !bullets.isEmpty || !numbered.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "– "] where line.hasPrefix(marker) {
            let rest = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            // "- [ ] task" → plain item
            return rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") ? String(rest.dropFirst(4)) : rest
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
              line.distance(from: line.startIndex, to: dot) <= 2,
              line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.first == " " else { return nil }
        return (String(line[..<dot]) + ".", rest.trimmingCharacters(in: .whitespaces))
    }
}
