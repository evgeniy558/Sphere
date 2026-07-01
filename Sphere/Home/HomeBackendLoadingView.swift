import SwiftUI

/// Backend loading placeholder for Home screen (before recommendations are ready).
struct HomeBackendLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShimmerLine(width: 210, height: 44)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ShimmerLine(width: 130, height: 14)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            ShimmerRect(corner: 18, width: nil, height: 118)
                .padding(.horizontal, 16)

            ShimmerLine(width: 120, height: 14)
                .padding(.horizontal, 18)
                .padding(.top, 4)

            HStack(spacing: 12) {
                ShimmerRect(corner: 16, width: 110, height: 110)
                ShimmerRect(corner: 16, width: 110, height: 110)
                ShimmerRect(corner: 16, width: 110, height: 110)
            }
            .padding(.horizontal, 16)

            ShimmerLine(width: 150, height: 14)
                .padding(.horizontal, 18)
                .padding(.top, 4)

            ShimmerLine(width: 190, height: 12)
                .padding(.horizontal, 18)

            HStack(spacing: 12) {
                ShimmerRect(corner: 16, width: 110, height: 110)
                ShimmerRect(corner: 16, width: 110, height: 110)
                ShimmerRect(corner: 16, width: 110, height: 110)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
