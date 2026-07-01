import Foundation

// MARK: - Daily Mixes

struct DailyMix: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String
    let seed: String?
    let coverURL: String?
    let tracks: [CatalogTrack]

    enum CodingKeys: String, CodingKey {
        case name, seed, tracks
        case coverURL = "cover_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        seed = try? c.decode(String.self, forKey: .seed)
        coverURL = try? c.decode(String.self, forKey: .coverURL)
        tracks = (try? c.decode([CatalogTrack].self, forKey: .tracks)) ?? []
    }

    /// First track cover used as the mix artwork base.
    var artworkCoverURL: String? {
        tracks.first?.coverURL ?? coverURL
    }

    /// Dominant genre from the first tracks with genre metadata.
    var primaryGenre: String? {
        for track in tracks.prefix(8) {
            if let genre = track.genres?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !genre.isEmpty {
                return genre
            }
        }
        return nil
    }

    var totalDurationSeconds: Int {
        tracks.reduce(0) { $0 + max($1.duration, 0) }
    }

    func formattedTotalDuration(isEnglish: Bool) -> String {
        let seconds = totalDurationSeconds
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            if isEnglish {
                return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
            }
            return minutes > 0 ? "\(hours) ч. \(minutes) мин." : "\(hours) ч."
        }
        return isEnglish ? "\(minutes) min" : "\(minutes) мин."
    }

    /// Comma-separated artist names for the mix subtitle (up to three unique names).
    var artistsLine: String {
        var seen = Set<String>()
        var names: [String] = []
        for track in tracks.prefix(16) {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(name)
            if names.count >= 3 { break }
        }
        return names.joined(separator: ", ")
    }

    /// Badge label for overlay: `MIX 1` (number) or `MIX ROCK` (genre fallback).
    func badgeLabel(mixIndex: Int) -> String {
        if let parsed = Self.parsedMixNumber(from: name) {
            return "MIX \(parsed)"
        }
        if mixIndex > 0 {
            return "MIX \(mixIndex)"
        }
        if let genre = primaryGenre {
            let upper = genre.uppercased()
            let short = upper.count > 14 ? String(upper.prefix(12)) : upper
            return "MIX \(short)"
        }
        return "MIX"
    }

    private static func parsedMixNumber(from name: String) -> Int? {
        let pattern = #"(?i)mix\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: name),
              let value = Int(name[range]) else { return nil }
        return value
    }
}

struct DailyMixesResponse: Decodable {
    let mixes: [DailyMix]
}

// MARK: - Download manifest

struct DownloadManifestItem: Codable, Identifiable, Equatable {
    let provider: String
    let id: String
    let title: String
    let artist: String
    let coverURL: String?
    let downloadURL: String

    var compositeKey: String { "\(provider):\(id)" }

    enum CodingKeys: String, CodingKey {
        case provider, id, title, artist
        case coverURL = "cover_url"
        case downloadURL = "download_url"
    }
}

struct DownloadManifestResponse: Decodable {
    let tracks: [DownloadManifestItem]
}

// MARK: - Wave

struct WaveTasteProfile: Codable {
    let user_id: String
    let genre_weights: [String: Double]?
    let artist_weights: [String: Double]?
    let provider_weights: [String: Double]?
    let energy_pref: Double
    let valence_pref: Double
    let tempo_pref: Double
}

struct WaveSessionResponse: Codable {
    let session_id: String
    let profile: WaveTasteProfile?
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case session_id, profile, created_at
    }
}

struct WaveNextResponse: Decodable {
    let tracks: [WaveScoredTrack]
}

struct WaveScoredTrack: Decodable, Identifiable {
    var id: String { "\(track.provider):\(track.id)" }
    let track: CatalogTrack
    let score: Double
}

struct KaraokePrepareResponse: Decodable {
    let status: String
    let provider: String?
    let track_id: String?
}

struct KaraokeStatusResponse: Decodable {
    let status: String
    let message: String?
}

// MARK: - Group playlists

struct GroupPlaylist: Identifiable, Codable, Equatable {
    let id: String
    let owner_id: String
    let title: String
    let description: String
    let cover_url: String
    let is_public: Bool
    let created_at: String
    let updated_at: String
    let track_count: Int
    let role: String?
}

struct GroupPlaylistTrack: Identifiable, Codable, Equatable {
    let id: String
    let provider: String
    let track_id: String
    let title: String
    let artist: String
    let cover_url: String
    let duration: Int
    let added_by: String
    let position: Int
    let added_at: String

    var catalogTrack: CatalogTrack {
        CatalogTrack(
            id: track_id,
            provider: provider,
            title: title,
            artist: artist,
            album: nil,
            coverURL: cover_url.isEmpty ? nil : cover_url,
            duration: duration,
            streamURL: nil,
            previewURL: nil,
            clipURL: nil,
            genres: nil,
            playCount: nil
        )
    }
}

struct GroupPlaylistMember: Identifiable, Codable, Equatable {
    var id: String { user_id }
    let user_id: String
    let username: String
    let name: String
    let avatar_url: String
    let role: String
}

struct GroupPlaylistDetail: Codable {
    let id: String
    let owner_id: String
    let title: String
    let description: String
    let cover_url: String
    let is_public: Bool
    let created_at: String
    let updated_at: String
    let track_count: Int
    let tracks: [GroupPlaylistTrack]
    let members: [GroupPlaylistMember]?
}

// MARK: - Blends

struct BlendSummary: Identifiable, Codable, Equatable {
    let id: String
    let creator_id: String
    let title: String
    let status: String
    let last_generated_at: String?
    let created_at: String
}

struct BlendsListResponse: Decodable {
    let blends: [BlendSummary]
}

struct BlendMember: Codable, Identifiable, Equatable {
    var id: String { user_id }
    let user_id: String
    let username: String
    let name: String
    let avatar_url: String
    let status: String
}

struct BlendTrack: Identifiable, Codable, Equatable {
    let id: String
    let provider: String
    let track_id: String
    let title: String
    let artist: String
    let cover_url: String
    let duration: Int
    let match_score: Double
    let match_label: String
    let position: Int

    var catalogTrack: CatalogTrack {
        CatalogTrack(
            id: track_id,
            provider: provider,
            title: title,
            artist: artist,
            album: nil,
            coverURL: cover_url.isEmpty ? nil : cover_url,
            duration: duration,
            streamURL: nil,
            previewURL: nil,
            clipURL: nil,
            genres: nil,
            playCount: nil
        )
    }
}

struct BlendDetail: Identifiable, Codable, Equatable {
    let id: String
    let creator_id: String
    let title: String
    let status: String
    let last_generated_at: String?
    let created_at: String
    let members: [BlendMember]?
    let tracks: [BlendTrack]?
}

// MARK: - Jam

struct JamSession: Identifiable, Codable, Equatable {
    let id: String
    let host_id: String
    let title: String
    let status: String
    let current_provider: String
    let current_track_id: String
    let current_position: Double
    let is_playing: Bool
    let participants: [JamParticipant]?
    let queue: [JamQueueItem]?
}

struct JamParticipant: Codable, Identifiable, Equatable {
    var id: String { user_id }
    let user_id: String
    let username: String
    let name: String
    let avatar_url: String
}

struct JamQueueItem: Identifiable, Codable, Equatable {
    let id: String
    let provider: String
    let track_id: String
    let title: String
    let artist: String
    let cover_url: String
    let duration: Int
    let added_by: String
    let position: Int
    let status: String
    let upvotes: Int
    let downvotes: Int
}

struct JamQueueResponse: Decodable {
    let queue: [JamQueueItem]
}

struct JamAddToQueueBody: Codable {
    let provider: String
    let track_id: String
}

struct JamVoteBody: Codable {
    let vote: String
}

struct JamInviteBody: Codable {
    let user_id: String
}

struct RegisterDeviceBody: Codable {
    let token: String
    let platform: String
}

struct WaveProfile: Codable {
    let total_plays: Int
    let total_minutes: Int
    let top_genres: [String]?
    let top_artists: [String]?
    let streak_days: Int
}

// MARK: - Uploads

struct UserUpload: Identifiable, Codable, Equatable {
    let id: String
    let user_id: String
    let title: String
    let artist_name: String
    let duration: Int
    let file_url: String
    let cover_url: String
    let file_size: Int64
    let created_at: String
}

// MARK: - Fans also like

struct FansAlsoLikeResponse: Decodable {
    let artists: [CatalogArtist]
}
