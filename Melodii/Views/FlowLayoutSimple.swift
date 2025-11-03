//
//  FlowLayoutSimple.swift
//  Melodii
//
//  A lightweight SwiftUI flow layout that wraps items across lines.
//

import SwiftUI

public struct FlowLayoutSimple<Data: RandomAccessCollection, Content: View>: View {
    private let data: Data
    private let spacing: CGFloat
    private let rowSpacing: CGFloat
    private let alignment: HorizontalAlignment
    private let content: (Data.Element) -> Content

    public init(
        _ data: Data,
        spacing: CGFloat = 8,
        rowSpacing: CGFloat = 8,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.alignment = alignment
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            self.generateContent(in: maxWidth)
        }
    }

    @ViewBuilder
    private func generateContent(in maxWidth: CGFloat) -> some View {
        var rows: [[Data.Element]] = []
        var currentRow: [Data.Element] = []

        // We need to measure each item; use an offscreen measuring container
        // Approach: build items, measure widths via preference, then layout.
        // For simplicity and to avoid complexity, we’ll do a best-effort estimation by laying out using flexible stacks.
        // A pragmatic alternative: pack items greedily using intrinsic sizes with a measuring helper.

        FlowRows(
            data: data,
            spacing: spacing,
            rowSpacing: rowSpacing,
            alignment: alignment,
            maxWidth: maxWidth,
            content: content
        )
    }
}

// Internal helper that actually performs the wrapping using a greedy algorithm with size measurement.
private struct FlowRows<Data: RandomAccessCollection, Content: View>: View {
    let data: Data
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let alignment: HorizontalAlignment
    let maxWidth: CGFloat
    let content: (Data.Element) -> Content

    @State private var sizes: [Int: CGSize] = [:]

    var body: some View {
        let rows = computeRows()

        VStack(alignment: alignment, spacing: rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.0) { index, element in
                        content(element)
                            .fixedSize() // ensure we measure intrinsic size
                            .background(
                                SizeMeasurer()
                                    .onPreferenceChange(SizePreferenceKey.self) { size in
                                        sizes[index] = size
                                    }
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
            }
        }
    }

    private func computeRows() -> [[(Int, Data.Element)]] {
        var rows: [[(Int, Data.Element)]] = []
        var currentRow: [(Int, Data.Element)] = []
        var currentWidth: CGFloat = 0

        let elements = Array(data.enumerated())
        for (i, element) in elements {
            let itemSize = sizes[i] ?? CGSize(width: 0, height: 0)
            let itemWidth = itemSize.width
            let nextWidth = currentRow.isEmpty ? itemWidth : currentWidth + spacing + itemWidth

            if nextWidth <= maxWidth || currentRow.isEmpty {
                currentRow.append((i, element))
                currentWidth = nextWidth
            } else {
                rows.append(currentRow)
                currentRow = [(i, element)]
                currentWidth = itemWidth
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

// A view that reports its size via preference
private struct SizeMeasurer: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: SizePreferenceKey.self, value: proxy.size)
        }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        // Prefer the latest measured size
        value = next == .zero ? value : next
    }
}

