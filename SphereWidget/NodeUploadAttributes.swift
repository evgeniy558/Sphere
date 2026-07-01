import Foundation
import ActivityKit

/// Shared Live Activity attributes for a Node Studio track upload.
///
/// IMPORTANT: this file is duplicated verbatim in the main `Sphere` target.
/// Both copies must stay identical so the app and the widget extension agree on
/// the Live Activity type.
struct NodeUploadAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 0.0 ... 1.0
        var progress: Double
        var statusText: String
        var finished: Bool
        var failed: Bool
    }

    var trackTitle: String
    var artistName: String
}
