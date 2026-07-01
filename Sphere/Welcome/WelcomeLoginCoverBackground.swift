import SwiftUI

struct WelcomeLoginCoverBackground: View {
    private let coverNames: [String] = (1...30).map { String(format: "NodeLoginCover%02d", $0) }
    @State private var randomizedRows: [[String]] = []

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let tileSize = min(max(width * 0.30, 96), 148)
            let rowCount = 6
            let verticalStep = tileSize + 14

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 14) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        WelcomeLoginCoverRow(
                            row: row,
                            names: rowNames(for: row),
                            tileSize: tileSize
                        )
                    }
                }
                .padding(.horizontal, -24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -verticalStep * 0.32)
                .opacity(0.92)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.60),
                        Color.black.opacity(0.90),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .onAppear {
            if randomizedRows.count != 6 {
                randomizedRows = (0..<6).map { _ in
                    coverNames.shuffled()
                }
            }
        }
    }

    private func rowNames(for row: Int) -> [String] {
        guard randomizedRows.indices.contains(row) else { return coverNames }
        return randomizedRows[row]
    }
}

private struct WelcomeLoginCoverRow: View {
    let row: Int
    let names: [String]
    let tileSize: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let spacing: CGFloat = 12
            let stride = tileSize + spacing
            let direction: CGFloat = row.isMultiple(of: 2) ? 1 : -1
            let baseSpeed: CGFloat = 15 + CGFloat(row % 3) * 2
            let visibleCount = max(Int(ceil(width / max(stride, 1))) + 4, 8)

            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                let t = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let total = CGFloat(visibleCount) * stride
                let travel = (t * baseSpeed).truncatingRemainder(dividingBy: max(total, 1))
                let xOffset = direction > 0 ? (travel - total) : -travel

                HStack(spacing: spacing) {
                    ForEach(0..<(visibleCount * 2), id: \.self) { idx in
                        let name = names.isEmpty ? "" : names[idx % names.count]
                        let phase = t * (0.55 + CGFloat((idx + row) % 4) * 0.08) + CGFloat(idx) * 0.45
                        let rotation = sin(phase) * 5 * direction
                        WelcomeLoginCoverTile(name: name, size: tileSize)
                            .rotationEffect(.degrees(rotation))
                    }
                }
                .offset(x: xOffset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: tileSize)
    }
}

private struct WelcomeLoginCoverTile: View {
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
            if !name.isEmpty {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}
