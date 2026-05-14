import SwiftUI
import Combine

/// Checks for app updates on launch and presents a release notes sheet.
/// "Install" button redirects to the Telegram distribution channel.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var pendingUpdate: AppUpdateInfo?

    private let lastSeenVersionKey = "sphere_last_seen_update_version"

    func checkForUpdates() async {
        do {
            guard let update = try await SphereAPIClient.shared.getLatestUpdate() else { return }
            let lastSeen = UserDefaults.standard.string(forKey: lastSeenVersionKey)
            if lastSeen != update.version {
                await MainActor.run { self.pendingUpdate = update }
            }
        } catch {
            // Silently ignore — non-critical feature.
        }
    }

    func markSeen() {
        if let v = pendingUpdate?.version {
            UserDefaults.standard.set(v, forKey: lastSeenVersionKey)
        }
        pendingUpdate = nil
    }
}

// MARK: - Update Sheet View

struct UpdateAvailableSheet: View {
    let update: AppUpdateInfo
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    private let telegramURL = URL(string: "https://t.me/nodemusicios")!

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(update.title.isEmpty ? "Update Available" : update.title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("v\(update.version)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)

            // Release notes body
            if !update.body.isEmpty {
                ScrollView {
                    Text(update.body)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }
                .frame(maxHeight: 300)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button {
                    UIApplication.shared.open(telegramURL)
                    UpdateChecker.shared.markSeen()
                    onDismiss()
                } label: {
                    Text("Install")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button {
                    UpdateChecker.shared.markSeen()
                    onDismiss()
                } label: {
                    Text("Later")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(isDark ? Color(white: 0.1) : Color(.systemBackground))
    }
}
