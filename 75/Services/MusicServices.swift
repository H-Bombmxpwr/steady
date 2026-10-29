import Foundation
import Observation
import AVFoundation
import AuthenticationServices
import CryptoKit
import UIKit

// MARK: - Apple catalog (search + previews)

/// Album search and 30-second previews through Apple's public iTunes Search
/// API — no key, no account. Spotify stopped serving previews to new apps, so
/// even a Spotify album plays through here.
enum RecordCatalog {
    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let collectionId: Int?
            let collectionName: String?
            let artistName: String?
            let artworkUrl100: String?
            let previewUrl: String?
            let wrapperType: String?
            let trackName: String?
            let trackNumber: Int?
            let discNumber: Int?
        }
        let results: [Item]
    }

    private static func get(_ path: String, _ query: [String: String]) async throws -> [SearchResponse.Item] {
        var comps = URLComponents(string: "https://itunes.apple.com/\(path)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(SearchResponse.self, from: data).results
    }

    /// Bigger artwork than the 100px the search hands back.
    static func largeArt(_ url: String?) -> String? {
        url?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
    }

    static func searchAlbums(_ term: String) async throws -> [CollectedRecord] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let items = try await get("search", ["term": trimmed, "entity": "album",
                                             "media": "music", "limit": "25"])
        return items.compactMap { item in
            guard let id = item.collectionId, let title = item.collectionName else { return nil }
            return CollectedRecord(id: "itunes:\(id)", title: title,
                                   artist: item.artistName ?? "",
                                   artworkURL: largeArt(item.artworkUrl100))
        }
    }

    /// The previewable tracks on a record's album, in album order. A Spotify
    /// record is found by searching songs, not albums — Apple's album search
    /// ranks loosely ("Khalid American Teen" puts Camila Cabello first) — and
    /// only an album whose artist and title actually match is accepted.
    struct Track: Hashable {
        let name: String
        let url: URL
    }

    static func previews(for record: CollectedRecord) async -> (collection: Int, tracks: [Track])? {
        guard let collection = await collectionID(for: record),
              let items = try? await get("lookup", ["id": "\(collection)", "entity": "song", "limit": "200"])
        else { return nil }
        let tracks = items
            .filter { $0.wrapperType == "track" && $0.collectionId == collection && $0.previewUrl != nil }
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 999) < ($1.discNumber ?? 1, $1.trackNumber ?? 999) }
            .compactMap { item in
                item.previewUrl.flatMap(URL.init(string:)).map { Track(name: item.trackName ?? "Untitled", url: $0) }
            }
        return tracks.isEmpty ? nil : (collection, tracks)
    }

    private static func collectionID(for record: CollectedRecord) async -> Int? {
        if record.id.hasPrefix("itunes:") { return Int(record.id.dropFirst("itunes:".count)) }
        if let known = record.catalogID { return known }
        let term = "\(record.artist) \(record.title)"
        let title = normalized(record.title), artist = normalized(record.artist)
        func matches(_ item: SearchResponse.Item) -> (exact: Bool, ok: Bool) {
            let t = normalized(item.collectionName ?? ""), a = normalized(item.artistName ?? "")
            let artistOK = !a.isEmpty && (a.contains(artist) || artist.contains(a))
            let titleOK = !t.isEmpty && (t.contains(title) || title.contains(t))
            return (artistOK && t == title, artistOK && titleOK)
        }
        for entity in ["song", "album"] {
            guard let items = try? await get("search", ["term": term, "entity": entity,
                                                        "media": "music", "limit": "50"]) else { continue }
            if let hit = items.first(where: { matches($0).exact }) ?? items.first(where: { matches($0).ok }) {
                return hit.collectionId
            }
        }
        return nil
    }

    /// Lowercased, accents and punctuation gone, and the edition noise that
    /// differs between Spotify and Apple dropped: "(Deluxe)", " - Single"…
    private static func normalized(_ s: String) -> String {
        var s = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        s = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+-\s+(single|ep)$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&", with: "and")
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

// MARK: - Player

/// The deck. One record at a time: it drops the needle on a random track,
/// plays 30-second previews through the rest of the album, and lifts when it
/// comes back round to where it started.
@MainActor
@Observable
final class RecordPlayer {
    static let shared = RecordPlayer()

    private(set) var playingID: String?
    private(set) var loadingID: String?
    /// The record on the deck, its tracks, and which one is playing.
    private(set) var record: CollectedRecord?
    private(set) var tracks: [RecordCatalog.Track] = []
    private(set) var index = 0
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 30
    /// Set when a record has no previews in Apple's catalog, so the panel can say so.
    private(set) var unavailable: CollectedRecord?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var startIndex = 0
    /// Each album's previews, fetched once per launch.
    private var cache: [String: [RecordCatalog.Track]] = [:]

    var isPlaying: Bool { playingID != nil }
    var track: RecordCatalog.Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var remaining: Double { max(0, duration - elapsed) }

    func toggle(_ record: CollectedRecord) {
        if playingID == record.id { stop() } else { Task { await play(record) } }
    }

    func play(_ record: CollectedRecord) async {
        stop()
        loadingID = record.id
        self.record = record
        if cache[record.id] == nil, let found = await RecordCatalog.previews(for: record) {
            cache[record.id] = found.tracks
            BuddyStore.shared.updateCatalogID(for: record.id, to: found.collection)
        }
        guard loadingID == record.id else { return }   // something else was tapped meanwhile
        loadingID = nil
        guard let found = cache[record.id], !found.isEmpty else {
            self.record = nil
            unavailable = record
            return
        }
        tracks = found
        // A different track from the album every time it's played.
        startIndex = Int.random(in: 0..<found.count)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        playingID = record.id
        start(at: startIndex)
    }

    func next() { skip(by: 1) }

    /// Back to the start of this track, or to the one before if it's barely begun.
    func previous() {
        if elapsed > 3 { player?.seek(to: .zero); elapsed = 0 } else { skip(by: -1) }
    }

    func stop() {
        tearDownItem()
        player = nil
        playingID = nil
        loadingID = nil
        record = nil
        tracks = []
        unavailable = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func skip(by step: Int) {
        guard isPlaying, !tracks.isEmpty else { return }
        start(at: (index + step + tracks.count) % tracks.count)
    }

    private func start(at i: Int) {
        tearDownItem()
        index = i
        elapsed = 0
        duration = 30
        let item = AVPlayerItem(url: tracks[i].url)
        let player = self.player ?? AVPlayer()
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.trackEnded() }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duration = d }
            }
        }
        self.player = player
        player.play()
    }

    private func trackEnded() {
        let upNext = (index + 1) % tracks.count
        if upNext == startIndex { stop() } else { start(at: upNext) }
    }

    private func tearDownItem() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

// MARK: - Spotify

/// Links a Spotify account (OAuth with PKCE — no server, no secret) and turns
/// what you actually listen to into the order records are earned in:
/// albums you've saved but rarely play come first, your most-played album
/// comes last, as the reward for finishing a tour.
@MainActor
@Observable
final class SpotifyLink: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyLink()

    static let clientIDKey = "spotify.clientID"
    static let redirectURI = "seventyfive://spotify-callback"
    private static let scopes = "user-top-read user-library-read"
    private static let keychainService = "com.hunter.steady.spotify"

    private(set) var busy = false
    var lastError: String?
    private(set) var isLinked: Bool
    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    private override init() {
        isLinked = Self.readRefreshToken() != nil
        super.init()
    }

    /// From Settings first, then a bundled one in Secrets.plist.
    static var clientID: String {
        let user = UserDefaults.standard.string(forKey: clientIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !user.isEmpty { return user }
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return "" }
        return (dict["SpotifyClientID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    // MARK: Link

    func link() async {
        let clientID = Self.clientID
        guard !clientID.isEmpty else {
            lastError = "Add a Spotify Client ID first — see the steps below."
            return
        }
        busy = true
        lastError = nil
        defer { busy = false }

        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes)
        ]

        do {
            let callback: URL = try await withCheckedThrowingContinuation { cont in
                let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "seventyfive") { url, error in
                    if let url { cont.resume(returning: url) }
                    else { cont.resume(throwing: error ?? URLError(.cancelled)) }
                }
                session.presentationContextProvider = self
                self.session = session
                session.start()
            }
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let denied = items.first(where: { $0.name == "error" })?.value {
                lastError = denied == "access_denied" ? "Spotify access was declined." : "Spotify said: \(denied)"
                return
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                lastError = "Spotify didn't send a code back."
                return
            }
            try await exchange(["grant_type": "authorization_code", "code": code,
                                "redirect_uri": Self.redirectURI, "client_id": clientID,
                                "code_verifier": verifier])
            isLinked = true
            await refreshQueue()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed the sheet — not an error worth showing.
        } catch {
            lastError = "Couldn't link Spotify: \(error.localizedDescription)"
        }
    }

    func unlink() {
        Self.deleteRefreshToken()
        accessToken = nil
        accessExpiry = .distantPast
        isLinked = false
    }

    // MARK: Listening → queue

    /// Rebuild the album queue from what you listen to.
    func refreshQueue() async {
        busy = true
        defer { busy = false }
        do {
            var scores: [String: (record: CollectedRecord, score: Double, isAlbum: Bool)] = [:]
            func add(_ album: SpotifyAlbum, _ score: Double) {
                guard let id = album.id else { return }
                let key = "spotify:\(id)"
                if var hit = scores[key] { hit.score += score; scores[key] = hit; return }
                let record = CollectedRecord(id: key, title: album.name ?? "Untitled",
                                             artist: album.artists?.first?.name ?? "",
                                             artworkURL: album.images?.first?.url,
                                             spotifyURL: album.external_urls?.spotify)
                scores[key] = (record, score, album.album_type != "single")
            }

            // Top tracks, weighted by rank and by how long the window is.
            for (range, weight) in [("long_term", 3.0), ("medium_term", 2.0), ("short_term", 1.0)] {
                let page: Page<SpotifyTrack> = try await api("me/top/tracks?time_range=\(range)&limit=50")
                for (i, track) in page.items.enumerated() {
                    if let album = track.album { add(album, Double(50 - i) * weight) }
                }
            }
            // Saved albums count as "yours" even with no plays — they're the
            // least-listened end of the queue, which is where it starts.
            let saved: Page<SavedAlbum> = try await api("me/albums?limit=50")
            for item in saved.items { if let album = item.album { add(album, 0) } }

            var albums = scores.values.filter(\.isAlbum)
            if albums.count < 10 { albums = Array(scores.values) }
            let queue = albums.sorted { $0.score < $1.score }.map(\.record)
            BuddyStore.shared.setSpotifyQueue(queue)
            lastError = queue.isEmpty ? "Spotify doesn't have enough listening history yet." : nil
        } catch {
            lastError = "Couldn't read your Spotify listening: \(error.localizedDescription)"
        }
    }

    // MARK: API plumbing

    private struct Page<T: Decodable>: Decodable { let items: [T] }
    private struct SpotifyTrack: Decodable { let album: SpotifyAlbum? }
    private struct SavedAlbum: Decodable { let album: SpotifyAlbum? }
    private struct SpotifyAlbum: Decodable {
        struct Artist: Decodable { let name: String? }
        struct Image: Decodable { let url: String? }
        struct Links: Decodable { let spotify: String? }
        let id: String?
        let name: String?
        let album_type: String?
        let artists: [Artist]?
        let images: [Image]?
        let external_urls: Links?
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func api<T: Decodable>(_ path: String) async throws -> T {
        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/\(path)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { unlink(); throw SpotifyError("Spotify signed you out — link it again.") }
        if status == 403 { throw SpotifyError("This Spotify account isn't on the app's allowlist. Add it under Users in the Spotify developer dashboard.") }
        guard status == 200 else { throw SpotifyError("Spotify returned an error (\(status)).") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validToken() async throws -> String {
        if let accessToken, accessExpiry > Date().addingTimeInterval(30) { return accessToken }
        guard let refresh = Self.readRefreshToken() else {
            isLinked = false
            throw SpotifyError("Spotify isn't linked.")
        }
        try await exchange(["grant_type": "refresh_token", "refresh_token": refresh,
                            "client_id": Self.clientID])
        guard let accessToken else { throw SpotifyError("Spotify didn't return a token.") }
        return accessToken
    }

    private func exchange(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if form["grant_type"] == "refresh_token" { unlink() }
            throw SpotifyError("Spotify wouldn't hand over a token. Check the Client ID and that \(Self.redirectURI) is listed as a Redirect URI.")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        accessExpiry = Date().addingTimeInterval(token.expires_in)
        if let refresh = token.refresh_token { Self.writeRefreshToken(refresh) }
    }

    private struct SpotifyError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    // MARK: Keychain

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "refresh"]
    }

    private static func readRefreshToken() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeRefreshToken(_ token: String) {
        deleteRefreshToken()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func deleteRefreshToken() {
        SecItemDelete(query as CFDictionary)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
