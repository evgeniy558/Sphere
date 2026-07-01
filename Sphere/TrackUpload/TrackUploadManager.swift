import Foundation
import Combine
import ActivityKit

/// Uploads a track to the Node backend on a background `URLSession` so the
/// transfer keeps running when the app is backgrounded, and mirrors progress
/// into a Live Activity (Dynamic Island + lock screen).
@MainActor
final class TrackUploadManager: NSObject, ObservableObject {
    static let shared = TrackUploadManager()

    @Published private(set) var isUploading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = ""
    @Published var lastError: String?
    @Published private(set) var lastUploadedTitle: String?

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.nodex.node.upload")
        cfg.isDiscretionary = false
        cfg.sessionSendsLaunchEvents = true
        cfg.allowsCellularAccess = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var currentTitle = ""
    private var currentArtist = ""
    private var bodyFileURL: URL?
    private var liveActivity: Any?  // Activity<NodeUploadAttributes> (gated by availability)

    private override init() { super.init() }

    var isLiveActivitySupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// Builds the multipart body and starts a background upload task.
    func upload(fileURL: URL, title: String, artistName: String, album: String = "", lyrics: String = "") {
        guard !isUploading else { return }
        let token = UserDefaults.standard.string(forKey: "sphereBackendJWT") ?? ""
        guard !token.isEmpty else {
            lastError = "Not signed in"
            return
        }
        guard let url = URL(string: SphereAPIClient.shared.baseURL + "/uploads") else {
            lastError = "Bad URL"
            return
        }

        // Access the security-scoped file and copy its bytes.
        let didScope = fileURL.startAccessingSecurityScopedResource()
        defer { if didScope { fileURL.stopAccessingSecurityScopedResource() } }

        let fileName = fileURL.lastPathComponent
        guard let fileData = try? Data(contentsOf: fileURL) else {
            lastError = "Cannot read file"
            return
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"title\"\r\n\r\n")
        append("\(title)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"artist_name\"\r\n\r\n")
        append("\(artistName)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"album\"\r\n\r\n")
        append("\(album)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"lyrics\"\r\n\r\n")
        append("\(lyrics)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType(for: fileName))\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        // Background upload tasks must read from a file.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).tmp")
        do {
            try body.write(to: tmp)
        } catch {
            lastError = "Cannot stage upload"
            return
        }
        bodyFileURL = tmp

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        currentTitle = title
        currentArtist = artistName
        isUploading = true
        progress = 0
        statusText = "Uploading…"
        lastError = nil

        startLiveActivity()

        let task = session.uploadTask(with: request, fromFile: tmp)
        task.resume()
    }

    private func mimeType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "m4a", "mp4", "aac": return "audio/mp4"
        case "wav": return "audio/wav"
        case "flac": return "audio/flac"
        case "aiff", "aif": return "audio/aiff"
        default: return "audio/mpeg"
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NodeUploadAttributes(trackTitle: currentTitle, artistName: currentArtist)
        let state = NodeUploadAttributes.ContentState(progress: 0, statusText: "Uploading…", finished: false, failed: false)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            liveActivity = activity
        } catch {
            liveActivity = nil
        }
    }

    private func updateLiveActivity(progress: Double, status: String, finished: Bool, failed: Bool) {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = liveActivity as? Activity<NodeUploadAttributes> else { return }
        let state = NodeUploadAttributes.ContentState(progress: progress, statusText: status, finished: finished, failed: failed)
        Task {
            if finished || failed {
                await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now + 4))
            } else {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    private func cleanupBodyFile() {
        if let f = bodyFileURL { try? FileManager.default.removeItem(at: f) }
        bodyFileURL = nil
    }
}

extension TrackUploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               didSendBodyData bytesSent: Int64,
                               totalBytesSent: Int64,
                               totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let p = min(1.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        Task { @MainActor in
            self.progress = p
            self.statusText = "Uploading… \(Int(p * 100))%"
            self.updateLiveActivity(progress: p, status: "Uploading… \(Int(p * 100))%", finished: false, failed: false)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let failed = error != nil
        let errText = error?.localizedDescription
        Task { @MainActor in
            self.cleanupBodyFile()
            self.isUploading = false
            if failed {
                self.statusText = "Upload failed"
                self.lastError = errText
                self.updateLiveActivity(progress: self.progress, status: "Upload failed", finished: false, failed: true)
            } else {
                self.progress = 1
                self.statusText = "Uploaded"
                self.lastUploadedTitle = self.currentTitle
                self.updateLiveActivity(progress: 1, status: "Uploaded", finished: true, failed: false)
            }
        }
    }
}
