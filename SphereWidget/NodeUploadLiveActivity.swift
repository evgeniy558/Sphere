import SwiftUI
import WidgetKit
import ActivityKit

/// Live Activity for an in-progress Node Studio track upload.
@available(iOSApplicationExtension 16.2, *)
struct NodeUploadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NodeUploadAttributes.self) { context in
            // Lock screen / banner
            NodeUploadLockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.failed ? "exclamationmark.triangle.fill"
                          : (context.state.finished ? "checkmark.circle.fill" : "arrow.up.circle.fill"))
                        .font(.title2)
                        .foregroundStyle(context.state.failed ? .red : .white)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.trackTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        ProgressView(value: context.state.progress)
                            .tint(.white)
                        Text(context.state.statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.white)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.white)
            }
            .keylineTint(.white)
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct NodeUploadLockScreenView: View {
    let context: ActivityViewContext<NodeUploadAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color.purple, Color.blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.trackTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.attributes.artistName.isEmpty ? "Node Studio" : context.attributes.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                ProgressView(value: context.state.progress)
                    .tint(context.state.failed ? .red : .white)
                Text(context.state.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            Text("\(Int(context.state.progress * 100))%")
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    private var iconName: String {
        if context.state.failed { return "exclamationmark.triangle.fill" }
        if context.state.finished { return "checkmark.circle.fill" }
        return "arrow.up.circle.fill"
    }
}
