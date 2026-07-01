import Foundation

/// Helpers for catalog stream URLs returned by the Node backend.
enum CatalogPlayback {
    /// SoundCloud search results expose a transcoding resolver URL, not raw audio bytes.
    static func isProviderStreamEndpoint(_ urlString: String) -> Bool {
        let s = urlString.lowercased()
        if s.contains("api.soundcloud.com") { return true }
        if s.contains("/transcodings/") { return true }
        if s.contains("soundcloud.com/transcoding") { return true }
        return false
    }

    /// Providers that must always play through the backend `/audio` proxy (expiring or IP-locked URLs).
    static func requiresBackendAudioProxy(provider: String) -> Bool {
        switch provider.lowercased() {
        case "youtube", "spotify", "deezer":
            return true
        default:
            return false
        }
    }

    /// Whether AVPlayer can open the URL directly (CDN mp3/m4a/ogg, HLS). Never googlevideo — URLs expire in minutes.
    static func isDirectPlayableURL(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        if isProviderStreamEndpoint(s) { return false }
        if s.contains("googlevideo.com") || s.contains("youtube.com/videoplayback") { return false }
        if s.contains(".m3u8") { return true }
        if s.contains("sndcdn.com") || s.contains("cf-media.sndcdn.com") { return true }
        if s.hasSuffix(".mp3") || s.hasSuffix(".m4a") || s.hasSuffix(".ogg") || s.hasSuffix(".aac") {
            return true
        }
        if s.contains("/preview") || s.contains("p.scdn.co") || s.contains("audio-preview") {
            return true
        }
        if s.contains("/stream?") && !isProviderStreamEndpoint(s) { return true }
        return false
    }

    static func proxyAudioURL(baseURL: String, track: CatalogTrack, lossless: Bool) -> URL? {
        let escapedProvider = track.provider.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? track.provider
        let escapedId = track.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? track.id
        let qualitySuffix = lossless ? "?quality=flac" : ""
        return URL(string: "\(baseURL)/tracks/\(escapedProvider)/\(escapedId)/audio\(qualitySuffix)")
    }
}
