import SwiftUI

/// A chat answer in Markdown: headings, lists, tables, quotes and code, with tappable links.
struct MarkdownText: View {
    let blocks: [MarkdownBlock]

    init(_ markdown: String) {
        blocks = MarkdownBlock.parse(markdown)
    }

    private static let listIndent: CGFloat = 14
    private static let quoteBarWidth: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                block(blocks[index])
            }
        }
        .font(.subheadline)
        .foregroundStyle(JellyCastColors.text)
        .tint(JellyCastColors.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownBlock.inline(text))
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .paragraph(let text):
            Text(MarkdownBlock.inline(text))
        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: marker).foregroundStyle(JellyCastColors.textMuted).monospacedDigit()
                Text(MarkdownBlock.inline(text)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * Self.listIndent)
        case .quote(let text):
            Text(MarkdownBlock.inline(text))
                .foregroundStyle(JellyCastColors.textMuted)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(JellyCastColors.rail).frame(width: Self.quoteBarWidth)
                }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(verbatim: code).font(.footnote.monospaced()).padding(10)
            }
            .scrollIndicators(.hidden)
            .background(JellyCastColors.surface, in: .rect(cornerRadius: 8))
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        case .rule:
            Rectangle().fill(JellyCastColors.rail).frame(height: 1)
        }
    }
}

/// Scrolls sideways when the columns are wider than the chat.
private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    private static let wrapAfterCharacters = 28
    private static let headerRuleHeight: CGFloat = 2

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                row(header, isHeader: true)
                divider(height: Self.headerRuleHeight)
                ForEach(rows.indices, id: \.self) { index in
                    if index > 0 { divider(height: 1) }
                    row(rows[index], isHeader: false)
                }
            }
            .background(JellyCastColors.surface, in: .rect(cornerRadius: 8))
        }
        .scrollIndicators(.hidden)
    }

    private func divider(height: CGFloat) -> some View {
        Rectangle().fill(JellyCastColors.rail).frame(height: height).gridCellUnsizedAxes(.horizontal)
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        GridRow {
            ForEach(cells.indices, id: \.self) { index in
                Text(MarkdownBlock.inline(cells[index]))
                    .font(isHeader ? .footnote.weight(.semibold) : .footnote)
                    .foregroundStyle(JellyCastColors.text)
                    .modifier(CellWidth(wraps: cells[index].count > Self.wrapAfterCharacters))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// The sideways scroll gives a cell all the width it wants, so a long one gets a fixed width to wrap in.
private struct CellWidth: ViewModifier {
    let wraps: Bool

    private static let wrappingWidth: CGFloat = 200

    func body(content: Content) -> some View {
        if wraps {
            content.frame(width: Self.wrappingWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        } else {
            content.fixedSize()
        }
    }
}

#Preview {
    ScrollView {
        MarkdownText("""
        ## Who is who
        Mostly **Walter** and *Jesse*, see [IMDb](https://www.imdb.com/title/tt0903747/).

        - Walter White, a chemistry teacher
          - also Heisenberg
        - Jesse Pinkman

        | Actor | Role | Season |
        |---|---|---|
        | Bryan Cranston | Walter White | 1–5 |
        | Aaron Paul | Jesse Pinkman | 1–5 |

        > Say my name.

        1. First
        2. Second
        """)
        .padding()
    }
    .background(JellyCastColors.background)
    .preferredColorScheme(.dark)
}
