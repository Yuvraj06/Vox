import SwiftUI

/// One planned change as a trail of chips: Home > Movies Watched > Dune.
/// The last chip is the item itself, tinted by what happens to it.
struct PlanStepRow: View {
    let step: PlanStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.verb.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(step.verb.tint)
                .frame(width: 26, height: 26)
                .background(step.verb.tint.opacity(0.18), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 4) {
                    if step.path.isEmpty {
                        PathChip { Image(systemName: "house.fill") }
                        Separator()
                    }
                    ForEach(Array(step.path.enumerated()), id: \.offset) { _, title in
                        PathChip { Text(title) }
                        Separator()
                    }
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(step.verb.tint.opacity(0.28), in: .capsule)
                        .overlay { Capsule().strokeBorder(step.verb.tint.opacity(0.5), lineWidth: 1) }
                        .strikethrough(step.verb == .delete)
                }
                if let note = step.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let place = step.path.isEmpty ? "top level" : step.path.joined(separator: ", ")
        return "\(step.verb.rawValue) \(step.title) in \(place)" + (step.note.map { ", \($0)" } ?? "")
    }
}

private struct PathChip<Label: View>: View {
    @ViewBuilder let label: Label

    var body: some View {
        label
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: .capsule)
    }
}

private struct Separator: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
    }
}

extension PlanStep.Verb {
    var tint: Color {
        switch self {
        case .add: TaskStatus.done.tint
        case .create: TaskStatus.doing.tint
        case .change, .move, .rename: TaskStatus.todo.tint
        case .delete: .red
        }
    }
}

/// Lays children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
