import SwiftUI

struct SkeletonView: View {
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            Rectangle()
                .fill(AppTheme.surfaceMuted)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            AppTheme.surfaceMuted.opacity(0.0),
                            Color.white.opacity(0.35),
                            AppTheme.surfaceMuted.opacity(0.0),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: shimmerOffset * width)
                    .clipped()
                )
                .clipped()
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.5).repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 1.6
            }
        }
    }
}

extension View {
    func skeleton(isLoading: Bool) -> some View {
        overlay(
            Group {
                if isLoading {
                    SkeletonView()
                        .cornerRadius(8)
                }
            }
        )
    }
}

struct SkeletonTransactionRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SkeletonView()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                SkeletonView()
                    .frame(width: 120, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                SkeletonView()
                    .frame(width: 60, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Spacer()

            SkeletonView()
                .frame(width: 80, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct SkeletonAccountCard: View {
    var body: some View {
        SkeletonView()
            .frame(width: 150, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
