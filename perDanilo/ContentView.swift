//
//  ContentView.swift
//  perDanilo
//
//  Created by Natasha Sgro on 14/10/26.
//

import SwiftUI
import Security
import WebKit

private enum FilmPalette {
    static let canvas = Color(red: 0.10, green: 0.13, blue: 0.22)
    static let ink = Color(red: 0.13, green: 0.18, blue: 0.32)
    static let muted = Color(red: 0.48, green: 0.48, blue: 0.44)
    static let mutedOnDark = Color(red: 0.72, green: 0.71, blue: 0.68)
    static let accent = Color(red: 0.94, green: 0.65, blue: 0.24)
    static let line = Color(red: 0.87, green: 0.83, blue: 0.75)
    static let softGreen = Color(red: 0.77, green: 0.84, blue: 0.72)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let listSurface = Color(red: 0.16, green: 0.20, blue: 0.31)
}

private struct Movie: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String
    let voteAverage: Double

    var year: Int? { Int(releaseDate.prefix(4)) }
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
    }
}

private struct WatchedMovie: Codable, Identifiable {
    var movie: Movie
    var rating: Int = 0
    var notes = ""
    var watchedAt = Date()
    var id: Int { movie.id }

    private enum CodingKeys: String, CodingKey {
        case movie, rating, notes, watchedAt
    }

    init(movie: Movie, rating: Int = 0, notes: String = "", watchedAt: Date = .now) {
        self.movie = movie
        self.rating = rating
        self.notes = notes
        self.watchedAt = watchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        movie = try container.decode(Movie.self, forKey: .movie)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        watchedAt = try container.decodeIfPresent(Date.self, forKey: .watchedAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(movie, forKey: .movie)
        try container.encode(rating, forKey: .rating)
        try container.encode(notes, forKey: .notes)
        try container.encode(watchedAt, forKey: .watchedAt)
    }
}

private struct MoviePage: Decodable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [Movie]

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

private struct MovieGenre: Decodable, Identifiable {
    let id: Int
    let name: String
}

private struct MovieGenreList: Decodable {
    let genres: [MovieGenre]
}

private struct MovieCountry: Decodable, Identifiable, Hashable {
    let code: String
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code = "iso_3166_1"
    }
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case italian = "it"
    case english = "en"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portuguese = "pt"
    case japanese = "ja"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .italian: "Italiano"
        case .english: "English"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .japanese: "日本語"
        }
    }

    var tmdbCode: String {
        switch self {
        case .italian: "it-IT"
        case .english: "en-US"
        case .french: "fr-FR"
        case .german: "de-DE"
        case .spanish: "es-ES"
        case .portuguese: "pt-PT"
        case .japanese: "ja-JP"
        }
    }

    var videoLanguages: String {
        rawValue == "en" ? "en" : "\(rawValue),en"
    }

    var flagRegionCode: String {
        switch self {
        case .italian: "IT"
        case .english: "US"
        case .french: "FR"
        case .german: "DE"
        case .spanish: "ES"
        case .portuguese: "PT"
        case .japanese: "JP"
        }
    }

    var flag: String { countryFlag(for: flagRegionCode) }
}

@MainActor
private final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "film.language") }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "film.language") ?? AppLanguage.italian.rawValue
        language = AppLanguage(rawValue: stored) ?? .italian
    }
}

@MainActor
private enum CountryNames {
    static var locale: Locale { Locale(identifier: AppSettings.shared.language.rawValue) }

    static func name(for code: String) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }
}

private struct MovieCollectionInfo: Decodable {
    let id: Int
    let name: String
}

private struct ProductionCountry: Decodable {
    let code: String

    enum CodingKeys: String, CodingKey {
        case code = "iso_3166_1"
    }
}

private struct MovieDetails: Decodable {
    let genres: [MovieGenre]
    let runtime: Int?
    let status: String?
    let tagline: String?
    let originCountry: [String]
    let productionCountries: [ProductionCountry]
    let belongsToCollection: MovieCollectionInfo?
    let watchProviders: WatchProviderResponse?
    let videos: [MovieVideo]
    let cast: [MovieCastMember]

    var actingCast: [MovieCastMember] {
        cast
            .filter { $0.knownForDepartment == "Acting" && !$0.name.isEmpty }
            .sorted { $0.order < $1.order }
    }

    var originFlags: String {
        let codes = originCountry.isEmpty ? productionCountries.map(\.code) : originCountry
        return codes.map(countryFlag(for:)).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func trailer(preferredLanguage: String) -> MovieVideo? {
        videos
            .filter(\.isYouTubeTrailer)
            .max { $0.rank(preferredLanguage: preferredLanguage) < $1.rank(preferredLanguage: preferredLanguage) }
    }

    enum CodingKeys: String, CodingKey {
        case genres, runtime, status, tagline, videos, credits
        case originCountry = "origin_country"
        case productionCountries = "production_countries"
        case belongsToCollection = "belongs_to_collection"
        case watchProviders = "watch/providers"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genres = try container.decodeIfPresent([MovieGenre].self, forKey: .genres) ?? []
        runtime = try container.decodeIfPresent(Int.self, forKey: .runtime)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
        originCountry = try container.decodeIfPresent([String].self, forKey: .originCountry) ?? []
        productionCountries = try container.decodeIfPresent([ProductionCountry].self, forKey: .productionCountries) ?? []
        belongsToCollection = try container.decodeIfPresent(MovieCollectionInfo.self, forKey: .belongsToCollection)
        watchProviders = try? container.decode(WatchProviderResponse.self, forKey: .watchProviders)
        videos = (try? container.decode(MovieVideoList.self, forKey: .videos))?.results ?? []
        cast = (try? container.decode(MovieCredits.self, forKey: .credits))?.cast ?? []
    }
}

private struct MovieCredits: Decodable {
    let cast: [MovieCastMember]
}

private struct MovieCastMember: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?
    let knownForDepartment: String
    let order: Int

    var profileURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
    }

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        character = try container.decodeIfPresent(String.self, forKey: .character) ?? ""
        profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
        knownForDepartment = try container.decodeIfPresent(String.self, forKey: .knownForDepartment) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? .max
    }
}

private struct MovieVideoList: Decodable {
    let results: [MovieVideo]
}

private struct MovieVideo: Decodable, Identifiable {
    let id: String
    let key: String
    let site: String
    let type: String
    let official: Bool
    let language: String?

    var isYouTubeTrailer: Bool {
        site.caseInsensitiveCompare("YouTube") == .orderedSame
            && (type.caseInsensitiveCompare("Trailer") == .orderedSame || type.caseInsensitiveCompare("Teaser") == .orderedSame)
            && key.unicodeScalars.allSatisfy { CharacterSet.youtubeVideoID.contains($0) }
            && (6...20).contains(key.count)
    }

    func rank(preferredLanguage: String) -> Int {
        let typeScore = type.caseInsensitiveCompare("Trailer") == .orderedSame ? 20 : 10
        let languageScore = language == preferredLanguage ? 4 : language == "en" ? 2 : 0
        return typeScore + languageScore + (official ? 1 : 0)
    }

    enum CodingKeys: String, CodingKey {
        case id, key, site, type, official
        case language = "iso_639_1"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        site = try container.decodeIfPresent(String.self, forKey: .site) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        official = try container.decodeIfPresent(Bool.self, forKey: .official) ?? false
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }
}

private extension CharacterSet {
    static let youtubeVideoID = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
}

private struct MovieCollectionDetails: Decodable {
    let parts: [CollectionMovie]

    struct CollectionMovie: Decodable {
        let id: Int
        let title: String
        let overview: String
        let posterPath: String?
        let releaseDate: String
        let voteAverage: Double

        var movie: Movie {
            Movie(
                id: id,
                title: title,
                overview: overview,
                posterPath: posterPath,
                releaseDate: releaseDate,
                voteAverage: voteAverage
            )
        }

        enum CodingKeys: String, CodingKey {
            case id, title, overview
            case posterPath = "poster_path"
            case releaseDate = "release_date"
            case voteAverage = "vote_average"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
            posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
            releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate) ?? ""
            voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage) ?? 0
        }
    }
}

private func countryFlag(for code: String) -> String {
    let upper = code.uppercased()
    guard upper.count == 2, upper.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return "" }
    return upper.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
}

#if os(macOS)
private final class TrailerScrollForwarder {
    private weak var webView: WKWebView?
    private var monitor: Any?

    func start(on webView: WKWebView) {
        self.webView = webView
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.forward(event) ?? event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { stop() }

    private func forward(_ event: NSEvent) -> NSEvent? {
        guard let webView, event.window === webView.window else { return event }
        let point = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(point) else { return event }
        guard let scrollView = scrollableAncestor(of: webView) else { return event }
        scroll(scrollView, by: event)
        return nil
    }

    private func scrollableAncestor(of view: NSView) -> NSScrollView? {
        var current = view.superview
        var nearest: NSScrollView?
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                nearest = nearest ?? scrollView
                let contentHeight = scrollView.documentView?.frame.height ?? 0
                if contentHeight > scrollView.contentView.bounds.height + 1 {
                    return scrollView
                }
            }
            current = candidate.superview
        }
        return nearest
    }

    private func scroll(_ scrollView: NSScrollView, by event: NSEvent) {
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return }
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 18
        var origin = clip.bounds.origin
        origin.y += clip.isFlipped ? -event.scrollingDeltaY * factor : event.scrollingDeltaY * factor
        origin.x -= event.scrollingDeltaX * factor
        let maxY = max(0, document.frame.height - clip.bounds.height)
        let maxX = max(0, document.frame.width - clip.bounds.width)
        origin.y = min(max(0, origin.y), maxY)
        origin.x = min(max(0, origin.x), maxX)
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
#endif

private struct TrailerPlayer: View {
    let videoID: String

    var body: some View {
        TrailerWebView(videoID: videoID)
            .background(FilmPalette.ink)
    }
}

private struct TrailerWebView {
    let videoID: String
    private var baseURL: URL { URL(string: "https://app.perdanilo")! }

    private var html: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
        html, body { margin: 0; height: 100%; background: #0d1220; overflow: hidden; }
        iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
        </style>
        </head>
        <body>
        <iframe
          src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1&origin=https://app.perdanilo"
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin">
        </iframe>
        </body>
        </html>
        """
    }

    fileprivate func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #endif
        #if os(macOS)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }
}

#if os(macOS)
extension TrailerWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(videoID: videoID) }
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView()
        context.coordinator.scrollForwarder.start(on: webView)
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.scrollForwarder.start(on: webView)
        guard context.coordinator.videoID != videoID else { return }
        context.coordinator.videoID = videoID
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var videoID: String
        let scrollForwarder = TrailerScrollForwarder()
        init(videoID: String) { self.videoID = videoID }
    }
}
#else
extension TrailerWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(videoID: videoID) }
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.videoID != videoID else { return }
        context.coordinator.videoID = videoID
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator {
        var videoID: String
        init(videoID: String) { self.videoID = videoID }
    }
}
#endif

private struct WatchProvider: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let logoPath: String?
    let displayPriority: Int

    var logoURL: URL? {
        guard let logoPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }

    enum CodingKeys: String, CodingKey {
        case id = "provider_id"
        case name = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        logoPath = try container.decodeIfPresent(String.self, forKey: .logoPath)
        displayPriority = try container.decodeIfPresent(Int.self, forKey: .displayPriority) ?? 0
    }
}

private struct WatchProviderRegion: Decodable {
    let link: String?
    let flatrate: [WatchProvider]?
    let free: [WatchProvider]?
    let ads: [WatchProvider]?
    let rent: [WatchProvider]?
    let buy: [WatchProvider]?

    static let empty = WatchProviderRegion(link: nil, flatrate: nil, free: nil, ads: nil, rent: nil, buy: nil)

    var groups: [WatchProviderGroup] {
        [
            ("In abbonamento", flatrate),
            ("Gratis", free),
            ("Con pubblicità", ads),
            ("Noleggio", rent),
            ("Acquisto", buy)
        ].compactMap { title, providers in
            let items = (providers ?? []).sorted { $0.displayPriority < $1.displayPriority }
            guard !items.isEmpty else { return nil }
            return WatchProviderGroup(title: title, providers: items)
        }
    }
}

private struct WatchProviderGroup: Identifiable {
    let title: String
    let providers: [WatchProvider]
    var id: String { title }
}

private struct WatchProviderResponse: Decodable {
    let results: [String: WatchProviderRegion]

    func availability() -> MovieWatchAvailability {
        let preferred = Locale.current.region?.identifier ?? "IT"
        if let offers = results[preferred] {
            return MovieWatchAvailability(regionCode: preferred, offers: offers)
        }
        if preferred != "IT", let offers = results["IT"] {
            return MovieWatchAvailability(regionCode: "IT", offers: offers)
        }
        return MovieWatchAvailability(regionCode: preferred, offers: .empty)
    }
}

private struct MovieWatchAvailability {
    let regionCode: String
    let offers: WatchProviderRegion
}

private struct TMDBErrorResponse: Decodable {
    let statusMessage: String

    enum CodingKeys: String, CodingKey {
        case statusMessage = "status_message"
    }
}

private func discoverMovieCount(token: String, decade: Int?, openEnded: Bool, genreID: Int?, countryCode: String?, language: String) async -> Int? {
    var components = URLComponents(string: "https://api.themoviedb.org/3/discover/movie")!
    var queryItems = [
        URLQueryItem(name: "language", value: language),
        URLQueryItem(name: "include_adult", value: "false"),
        URLQueryItem(name: "page", value: "1")
    ]
    if let decade {
        queryItems.append(URLQueryItem(name: "primary_release_date.gte", value: String(format: "%04d-01-01", decade)))
        if !openEnded {
            queryItems.append(URLQueryItem(name: "primary_release_date.lte", value: String(format: "%04d-12-31", decade + 9)))
        }
    }
    if let genreID {
        queryItems.append(URLQueryItem(name: "with_genres", value: String(genreID)))
    }
    if let countryCode {
        queryItems.append(URLQueryItem(name: "with_origin_country", value: countryCode))
    }
    components.queryItems = queryItems
    guard let url = components.url else { return nil }

    do {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        return try JSONDecoder().decode(MoviePage.self, from: data).totalResults
    } catch {
        return nil
    }
}

private enum TokenVault {
    private static let service = "app.perDanilo.tmdb"
    private static let account = "read-access-token"

    static func read() -> String? {
        if UserDefaults.standard.bool(forKey: "film.tmdb.manual-token"),
           let token = readKeychainToken() {
            return normalized(token)
        }
        if let token = Bundle.main.object(forInfoDictionaryKey: "TMDB_READ_ACCESS_TOKEN") as? String,
           !normalized(token).isEmpty {
            save(token)
            return normalized(token)
        }
        return readKeychainToken().map(normalized)
    }

    private static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
          if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
             let data = result as? Data,
             let token = String(data: data, encoding: .utf8) {
            return token
          }
        return nil
    }

    static func save(_ token: String, asManualOverride: Bool = false) {
          let data = Data(normalized(token).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
        if asManualOverride {
            UserDefaults.standard.set(true, forKey: "film.tmdb.manual-token")
        }
    }

    static func normalized(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bearer ") else { return trimmed }
        return String(trimmed.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class MovieLibrary: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var searchResults: [Movie] = []
    @Published var movieGenres: [MovieGenre] = []
    @Published var movieCountries: [MovieCountry] = []
    @Published var availableDecadeIDs: Set<Int>?
    @Published var availableGenreIDs: Set<Int>?
    @Published var availableCountryCodes: Set<String>?
    @Published var isLoadingDecadeOptions = false
    @Published var isLoadingGenreOptions = false
    @Published var isLoadingCountryOptions = false
    @Published var isLoadingCountries = false
    @Published var watchlist: [Movie] = []
    @Published var watched: [WatchedMovie] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var isLoadingDecade = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var hasToken = TokenVault.read() != nil
    @Published var featuredMovie: Movie?

    private var nextPage = 1
    private var totalPages = 500
    private var searchNextPage = 1
    private var searchTotalPages = 1
    private var activeSearchQuery = ""
    private var searchGeneration = 0
    private var decadeNextPage = 1
    private var decadeTotalPages = 1
    private var activeDecade: Int?
    private var activeDecadeIsOpenEnded = false
    private var activeGenreID: Int?
    private var activeCountryCode: String?
    private var decadeGeneration = 0
    private var decadeOptionsGeneration = 0
    private var genreOptionsGeneration = 0
    private var countryOptionsGeneration = 0
    private var countryAvailabilityCache: [String: Set<String>] = [:]
    @Published var decadeResults: [Movie] = []
    private var dismissedMovieIDs = Set<Int>()

    init() {
        watchlist = Self.load("film.watchlist", as: [Movie].self) ?? []
        watched = Self.load("film.watched", as: [WatchedMovie].self) ?? []
    }

    func saveToken(_ token: String) {
        TokenVault.save(token, asManualOverride: true)
        hasToken = TokenVault.read() != nil
        errorMessage = nil
        Task { await loadNextPage() }
    }

    func applyLanguageChange() async {
        movieGenres = []
        searchResults = []
        decadeResults = []
        clearFilterAvailability()
        movies = []
        nextPage = 1
        totalPages = 500
        isLoading = false
        isLoadingDecade = false
        movieCountries.sort {
            CountryNames.name(for: $0.code).localizedStandardCompare(CountryNames.name(for: $1.code)) == .orderedAscending
        }
        await loadMovieGenres()
        await loadNextPage(refresh: true)
        await relocalizeSavedMovies()
    }

    func clearFilterAvailability() {
        availableDecadeIDs = nil
        availableGenreIDs = nil
        availableCountryCodes = nil
        countryAvailabilityCache = [:]
        isLoadingDecadeOptions = false
        isLoadingGenreOptions = false
        isLoadingCountryOptions = false
    }

    private func relocalizeSavedMovies() async {
        let currentWatchlist = watchlist
        let currentWatched = watched
        let featuredID = featuredMovie?.id
        let localizedWatchlist = await localizeMovies(currentWatchlist)
        let localizedWatched = await localizeWatched(currentWatched)
        watchlist = localizedWatchlist
        watched = localizedWatched
        if let featuredID, let localizedFeatured = await fetchLocalizedMovie(id: featuredID) {
            featuredMovie = localizedFeatured
        }
        persist(watchlist, key: "film.watchlist")
        persist(watched, key: "film.watched")
    }

    private func localizeMovies(_ movies: [Movie]) async -> [Movie] {
        var localizedByID: [Int: Movie] = [:]
        localizedByID.reserveCapacity(movies.count)
        for movie in movies {
            if let localized = await fetchLocalizedMovie(id: movie.id) {
                localizedByID[movie.id] = localized
            }
        }
        return movies.map { localizedByID[$0.id] ?? $0 }
    }

    private func localizeWatched(_ items: [WatchedMovie]) async -> [WatchedMovie] {
        let localizedMovies = await localizeMovies(items.map(\.movie))
        let byID = Dictionary(uniqueKeysWithValues: localizedMovies.map { ($0.id, $0) })
        return items.map { item in
            var updated = item
            if let movie = byID[item.id] {
                updated.movie = movie
            }
            return updated
        }
    }

    func fetchLocalizedMovie(id: Int) async -> Movie? {
        let languageCode = AppSettings.shared.language.tmdbCode
        guard let token = TokenVault.read(),
              let url = URL(string: "https://api.themoviedb.org/3/movie/\(id)?language=\(languageCode)") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
            return try JSONDecoder().decode(Movie.self, from: data)
        } catch {
            return nil
        }
    }

    func loadMovieGenres() async {
        guard hasToken, movieGenres.isEmpty,
              let url = URL(string: "https://api.themoviedb.org/3/genre/movie/list?language=\(AppSettings.shared.language.tmdbCode)"),
              let token = TokenVault.read() else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
            movieGenres = try JSONDecoder().decode(MovieGenreList.self, from: data).genres.sorted { $0.name < $1.name }
        } catch {
            errorMessage = "Errore caricamento generi: \(error.localizedDescription)"
        }
    }

    func loadMovieCountries() async {
        guard hasToken, movieCountries.isEmpty,
              let url = URL(string: "https://api.themoviedb.org/3/configuration/countries"),
              let token = TokenVault.read() else { return }
        isLoadingCountries = true
        defer { isLoadingCountries = false }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return }
            movieCountries = try JSONDecoder().decode([MovieCountry].self, from: data).sorted {
                CountryNames.name(for: $0.code).localizedStandardCompare(CountryNames.name(for: $1.code)) == .orderedAscending
            }
        } catch {
            errorMessage = "Errore caricamento paesi: \(error.localizedDescription)"
        }
    }

    func loadAvailableDecades(forGenre genreID: Int?, countryCode: String? = nil) async {
        decadeOptionsGeneration += 1
        let generation = decadeOptionsGeneration
        guard genreID != nil || countryCode != nil else {
            availableDecadeIDs = nil
            isLoadingDecadeOptions = false
            return
        }
        guard let token = TokenVault.read() else { return }

        // Non svuotare la select: tieni la lista attuale finché non arriva il risultato definitivo.
        isLoadingDecadeOptions = true
        defer {
            if generation == decadeOptionsGeneration { isLoadingDecadeOptions = false }
        }

        let currentYear = Calendar.current.component(.year, from: .now)
        let latestDecade = (currentYear / 10) * 10
        let decadeStarts = Array(stride(from: 1890, through: latestDecade, by: 10))
        let language = AppSettings.shared.language.tmdbCode
        let available = await withTaskGroup(of: (Int, Bool).self, returning: Set<Int>.self) { group in
            for decade in decadeStarts {
                group.addTask {
                    let count = await discoverMovieCount(
                        token: token,
                        decade: decade,
                        openEnded: decade == latestDecade,
                        genreID: genreID,
                        countryCode: countryCode,
                        language: language
                    )
                    return (decade, (count ?? 0) > 0)
                }
            }

            var matchingDecades = Set<Int>()
            for await (decade, hasResults) in group where hasResults {
                matchingDecades.insert(decade)
            }
            return matchingDecades
        }

        guard generation == decadeOptionsGeneration else { return }
        availableDecadeIDs = available
    }

    func loadAvailableGenres(forDecade decade: Int?, openEnded: Bool, countryCode: String? = nil) async {
        genreOptionsGeneration += 1
        let generation = genreOptionsGeneration
        guard decade != nil || countryCode != nil else {
            availableGenreIDs = nil
            isLoadingGenreOptions = false
            return
        }
        guard let token = TokenVault.read() else { return }

        // Non svuotare la select: tieni la lista attuale finché non arriva il risultato definitivo.
        isLoadingGenreOptions = true
        defer {
            if generation == genreOptionsGeneration { isLoadingGenreOptions = false }
        }

        let genres = movieGenres
        let language = AppSettings.shared.language.tmdbCode
        let available = await withTaskGroup(of: (Int, Bool).self, returning: Set<Int>.self) { group in
            for genre in genres {
                group.addTask {
                    let count = await discoverMovieCount(
                        token: token,
                        decade: decade,
                        openEnded: openEnded,
                        genreID: genre.id,
                        countryCode: countryCode,
                        language: language
                    )
                    return (genre.id, (count ?? 0) > 0)
                }
            }

            var matchingGenres = Set<Int>()
            for await (genreID, hasResults) in group where hasResults {
                matchingGenres.insert(genreID)
            }
            return matchingGenres
        }

        guard generation == genreOptionsGeneration else { return }
        availableGenreIDs = available
    }

    func loadAvailableCountries(forDecade decade: Int?, openEnded: Bool, genreID: Int? = nil) async {
        countryOptionsGeneration += 1
        let generation = countryOptionsGeneration
        guard decade != nil || genreID != nil else {
            availableCountryCodes = nil
            isLoadingCountryOptions = false
            return
        }
        if movieCountries.isEmpty {
            await loadMovieCountries()
        }
        let cacheKey = "\(decade ?? -1)-\(openEnded)-\(genreID ?? -1)"
        if let cached = countryAvailabilityCache[cacheKey] {
            availableCountryCodes = cached
            isLoadingCountryOptions = false
            return
        }
        guard let token = TokenVault.read() else { return }

        let countries = movieCountries
        guard !countries.isEmpty else {
            availableCountryCodes = nil
            isLoadingCountryOptions = false
            return
        }

        // Non svuotare la select: tieni la lista attuale finché non arriva il risultato definitivo.
        isLoadingCountryOptions = true
        defer {
            if generation == countryOptionsGeneration { isLoadingCountryOptions = false }
        }

        let language = AppSettings.shared.language.tmdbCode
        let maxConcurrent = 12
        let available = await withTaskGroup(of: (String, Bool).self, returning: Set<String>.self) { group in
            var iterator = countries.makeIterator()
            var matchingCountries = Set<String>()

            func enqueueNext() {
                guard let country = iterator.next() else { return }
                group.addTask {
                    let count = await discoverMovieCount(
                        token: token,
                        decade: decade,
                        openEnded: openEnded,
                        genreID: genreID,
                        countryCode: country.code,
                        language: language
                    )
                    return (country.code, (count ?? 0) > 0)
                }
            }

            for _ in 0..<min(maxConcurrent, countries.count) {
                enqueueNext()
            }
            while let (code, hasResults) = await group.next() {
                if hasResults { matchingCountries.insert(code) }
                enqueueNext()
            }
            return matchingCountries
        }

        guard generation == countryOptionsGeneration else { return }
        countryAvailabilityCache[cacheKey] = available
        availableCountryCodes = available
    }

    func loadNextPage(refresh: Bool = false) async {
        guard hasToken, !isLoading, refresh || nextPage <= totalPages else { return }
        isLoading = true
        defer { isLoading = false }

        let page = refresh || nextPage == 1 ? Int.random(in: 1...500) : nextPage
        var components = URLComponents(string: "https://api.themoviedb.org/3/movie/popular")!
        components.queryItems = [
            URLQueryItem(name: "language", value: AppSettings.shared.language.tmdbCode),
            URLQueryItem(name: "page", value: String(page))
        ]
        guard let url = components.url, let token = TokenVault.read() else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(response.statusCode) else {
                let apiMessage = (try? JSONDecoder().decode(TMDBErrorResponse.self, from: data))?.statusMessage
                errorMessage = apiMessage.map { "TMDB: \($0)" } ?? "TMDB ha risposto con errore HTTP \(response.statusCode)."
                return
            }
            let result = try JSONDecoder().decode(MoviePage.self, from: data)
            totalPages = min(result.totalPages, 500)
            nextPage = page + 1
            if refresh {
                movies = result.results.shuffled()
            } else {
                let knownIDs = Set(movies.map(\.id))
                movies.append(contentsOf: result.results.filter { !knownIDs.contains($0.id) }.shuffled())
            }
            errorMessage = nil
        } catch {
            errorMessage = "Errore di rete: \(error.localizedDescription)"
        }
    }

    func refreshMovies(query: String) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if query.isEmpty {
            await loadNextPage(refresh: true)
        } else {
            await searchMovies(query: query)
        }
    }

    func searchMovies(query: String, loadMore: Bool = false) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if loadMore {
            guard !normalizedQuery.isEmpty,
                  normalizedQuery == activeSearchQuery,
                  !isSearching,
                  searchNextPage <= searchTotalPages else { return }
            await performMovieSearch(query: normalizedQuery, page: searchNextPage, generation: searchGeneration)
            return
        }

        searchGeneration += 1
        activeSearchQuery = normalizedQuery
        searchNextPage = 1
        searchTotalPages = 1
        searchResults = []
        guard !normalizedQuery.isEmpty else { return }
        await performMovieSearch(query: normalizedQuery, page: 1, generation: searchGeneration)
    }

    func loadMovies(forDecade decade: Int?, genreID: Int? = nil, countryCode: String? = nil, openEnded: Bool = false, loadMore: Bool = false, refresh: Bool = false) async {
        if loadMore {
            guard activeDecade == decade,
                  activeDecadeIsOpenEnded == openEnded,
                  activeGenreID == genreID,
                  activeCountryCode == countryCode,
                  !isLoadingDecade,
                  decadeNextPage <= decadeTotalPages else { return }
            await performDecadeLoad(decade: decade, genreID: genreID, countryCode: countryCode, openEnded: openEnded, page: decadeNextPage, generation: decadeGeneration)
            return
        }

        decadeGeneration += 1
        activeDecade = decade
        activeDecadeIsOpenEnded = openEnded
        activeGenreID = genreID
        activeCountryCode = countryCode
        decadeNextPage = 1
        decadeTotalPages = 1
        if !refresh { decadeResults = [] }
        await performDecadeLoad(decade: decade, genreID: genreID, countryCode: countryCode, openEnded: openEnded, page: 1, generation: decadeGeneration)
    }

    func filtersStillMatch(decade: Int?, openEnded: Bool, genreID: Int?, countryCode: String?) async -> Bool {
        guard let token = TokenVault.read() else { return true }
        guard let count = await discoverMovieCount(
            token: token,
            decade: decade,
            openEnded: openEnded,
            genreID: genreID,
            countryCode: countryCode,
            language: AppSettings.shared.language.tmdbCode
        ) else { return true }
        return count > 0
    }

    private func performDecadeLoad(decade: Int?, genreID: Int?, countryCode: String?, openEnded: Bool, page: Int, generation: Int) async {
        guard hasToken else { return }
        isLoadingDecade = true
        defer {
            if generation == decadeGeneration { isLoadingDecade = false }
        }

        var components = URLComponents(string: "https://api.themoviedb.org/3/discover/movie")!
        var queryItems = [
            URLQueryItem(name: "language", value: AppSettings.shared.language.tmdbCode),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let decade {
            queryItems.append(URLQueryItem(name: "primary_release_date.gte", value: String(format: "%04d-01-01", decade)))
        }
        if let decade, !openEnded {
            queryItems.append(URLQueryItem(name: "primary_release_date.lte", value: String(format: "%04d-12-31", decade + 9)))
        }
        if let genreID {
            queryItems.append(URLQueryItem(name: "with_genres", value: String(genreID)))
        }
        if let countryCode {
            queryItems.append(URLQueryItem(name: "with_origin_country", value: countryCode))
        }
        components.queryItems = queryItems
        guard let url = components.url, let token = TokenVault.read() else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard generation == decadeGeneration,
                activeDecade == decade,
                activeDecadeIsOpenEnded == openEnded,
                activeGenreID == genreID,
                activeCountryCode == countryCode else { return }
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(response.statusCode) else {
                let message = (try? JSONDecoder().decode(TMDBErrorResponse.self, from: data))?.statusMessage
                errorMessage = message.map { "TMDB: \($0)" } ?? "TMDB ha risposto con errore HTTP \(response.statusCode)."
                return
            }
            let result = try JSONDecoder().decode(MoviePage.self, from: data)
            decadeTotalPages = min(result.totalPages, 500)
            decadeNextPage = page + 1
            let knownIDs = Set(decadeResults.map(\.id))
            if page == 1 {
                decadeResults = result.results
            } else {
                decadeResults.append(contentsOf: result.results.filter { !knownIDs.contains($0.id) })
            }
            errorMessage = nil
        } catch {
            guard generation == decadeGeneration, activeDecade == decade else { return }
            errorMessage = "Errore caricamento catalogo: \(error.localizedDescription)"
        }
    }

    func loadMovieDetails(id: Int) async -> MovieDetails? {
        let language = AppSettings.shared.language
        guard let token = TokenVault.read(),
              let url = URL(string: "https://api.themoviedb.org/3/movie/\(id)?language=\(language.tmdbCode)&include_video_language=\(language.videoLanguages)&append_to_response=credits,videos,watch/providers") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
            return try JSONDecoder().decode(MovieDetails.self, from: data)
        } catch {
            return nil
        }
    }

    func loadCollectionMovies(id: Int) async -> [Movie] {
        guard let token = TokenVault.read(),
              let url = URL(string: "https://api.themoviedb.org/3/collection/\(id)?language=\(AppSettings.shared.language.tmdbCode)") else { return [] }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return [] }
            return try JSONDecoder().decode(MovieCollectionDetails.self, from: data).parts
                .map(\.movie)
                .sorted { ($0.releaseDate.isEmpty ? "9999" : $0.releaseDate) < ($1.releaseDate.isEmpty ? "9999" : $1.releaseDate) }
        } catch {
            return []
        }
    }

    func loadWatchProviders(id: Int) async -> MovieWatchAvailability? {
        guard let token = TokenVault.read(),
              let url = URL(string: "https://api.themoviedb.org/3/movie/\(id)/watch/providers") else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
            let decoded = try JSONDecoder().decode(WatchProviderResponse.self, from: data)
            return decoded.availability()
        } catch {
            return nil
        }
    }

    private func performMovieSearch(query: String, page: Int, generation: Int) async {
        guard hasToken else { return }
        isSearching = true
        defer {
            if generation == searchGeneration { isSearching = false }
        }

        var components = URLComponents(string: "https://api.themoviedb.org/3/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "language", value: AppSettings.shared.language.tmdbCode),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        guard let url = components.url, let token = TokenVault.read() else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard generation == searchGeneration, query == activeSearchQuery else { return }
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(response.statusCode) else {
                let apiMessage = (try? JSONDecoder().decode(TMDBErrorResponse.self, from: data))?.statusMessage
                errorMessage = apiMessage.map { "TMDB: \($0)" } ?? "TMDB ha risposto con errore HTTP \(response.statusCode)."
                return
            }
            let result = try JSONDecoder().decode(MoviePage.self, from: data)
            searchTotalPages = min(result.totalPages, 500)
            searchNextPage = page + 1
            let knownIDs = Set(searchResults.map(\.id))
            searchResults.append(contentsOf: result.results.filter { !knownIDs.contains($0.id) })
            errorMessage = nil
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = "Errore di ricerca TMDB: \(error.localizedDescription)"
        }
    }

    func addToWatchlist(_ movie: Movie) {
        guard !watchlist.contains(where: { $0.id == movie.id }), !watched.contains(where: { $0.id == movie.id }) else { return }
        watchlist.insert(movie, at: 0)
        persist(watchlist, key: "film.watchlist")
    }

    func promoteToWatchlist(_ movie: Movie) {
        guard !watched.contains(where: { $0.id == movie.id }) else { return }
        watchlist.removeAll { $0.id == movie.id }
        watchlist.insert(movie, at: 0)
        featuredMovie = movie
        persist(watchlist, key: "film.watchlist")
    }

    func markWatched(_ movie: Movie, rating: Int = 0, notes: String = "") {
        guard !watched.contains(where: { $0.id == movie.id }) else { return }
        watched.insert(WatchedMovie(movie: movie, rating: rating, notes: notes), at: 0)
        watchlist.removeAll { $0.id == movie.id }
        persist(watchlist, key: "film.watchlist")
        persist(watched, key: "film.watched")
        if featuredMovie?.id == movie.id { featuredMovie = nil }
    }

    func updateReview(for id: Int, rating: Int? = nil, notes: String? = nil) {
        guard let index = watched.firstIndex(where: { $0.id == id }) else { return }
        if let rating { watched[index].rating = rating }
        if let notes { watched[index].notes = notes }
        persist(watched, key: "film.watched")
    }

    func generate(from tab: LibraryTab) {
        let candidates = tab == .watchlist ? watchlist : movies
        let watchedIDs = Set(watched.map(\.id))
        let choices = candidates.filter {
            !watchedIDs.contains($0.id) && !dismissedMovieIDs.contains($0.id)
        }
        if let choice = choices.randomElement() {
            featuredMovie = choice
        } else if tab == .all {
            Task { await loadNextPage() }
            errorMessage = "Hai visto tutti i film caricati. Sto cercando altri titoli."
        } else {
            errorMessage = "Aggiungi un film alla lista per poterlo estrarre."
        }
    }

    func dismissFeatured() {
        if let featuredMovie { dismissedMovieIDs.insert(featuredMovie.id) }
        featuredMovie = nil
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else { return nil }
        return value
    }
}

private enum LibraryTab: String, CaseIterable, Identifiable {
    case all = "Tutti"
    case watchlist = "Da vedere"
    case watched = "Visti"
    var id: String { rawValue }
}

private enum AppSheet: Identifiable {
    case tokenSetup
    case filmOfDay(Movie)
    case movieDetails(Movie, fromWatchlist: Bool)
    case watchReview(Movie)

    var id: String {
        switch self {
        case .tokenSetup: "token-setup"
        case .filmOfDay(let movie): "film-\(movie.id)"
        case .movieDetails(let movie, _): "details-\(movie.id)"
        case .watchReview(let movie): "review-\(movie.id)"
        }
    }
}

private enum WatchedSort: String, CaseIterable, Identifiable {
    case newest = "Più recenti"
    case oldest = "Meno recenti"
    case highestRated = "Voto più alto"
    case lowestRated = "Voto più basso"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .newest: "calendar"
        case .oldest: "calendar"
        case .highestRated: "star.fill"
        case .lowestRated: "star"
        }
    }
}

private enum WatchlistSort: String, CaseIterable, Identifiable {
    case recent = "Recenti"
    case newestYear = "Anno più recente"
    case oldestYear = "Anno meno recente"

    var id: String { rawValue }
}

private struct WindowSizing: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(minWidth: 760, minHeight: 560)
        #else
        content
        #endif
    }
}

private struct CompactPickerPresentation<PickerContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var arrowEdge: Edge = .bottom
    var macWidth: CGFloat
    var macHeight: CGFloat?
    @ViewBuilder var pickerContent: () -> PickerContent

    private var pickerWidth: CGFloat {
        #if os(iOS)
        max(macWidth, 280)
        #else
        macWidth
        #endif
    }

    private var pickerHeight: CGFloat? {
        guard let macHeight else { return nil }
        #if os(iOS)
        // Su iPhone il popover altrimenti resta alto ~3 voci.
        return max(macHeight, 420)
        #else
        return macHeight
        #endif
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
                Group {
                    if let pickerHeight {
                        pickerContent()
                            .frame(width: pickerWidth, height: pickerHeight, alignment: .top)
                    } else {
                        pickerContent()
                            .frame(width: pickerWidth)
                    }
                }
                .background(FilmPalette.paper)
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
            }
    }
}

private extension View {
    func compactPicker<PickerContent: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .bottom,
        macWidth: CGFloat,
        macHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> PickerContent
    ) -> some View {
        modifier(CompactPickerPresentation(
            isPresented: isPresented,
            arrowEdge: arrowEdge,
            macWidth: macWidth,
            macHeight: macHeight,
            pickerContent: content
        ))
    }
}

private struct DesktopPullToRefresh: ViewModifier {
    @Binding var isAtTop: Bool
    @Binding var pullDistance: CGFloat
    let onRefresh: () -> Void
    @State private var restingOffset: CGFloat?
    @State private var refreshArmed = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .scrollBounceBehavior(.always)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                if restingOffset == nil { restingOffset = offset }
                guard let restingOffset else { return }
                let pull = max(0, restingOffset - offset)
                isAtTop = offset <= restingOffset + 1
                pullDistance = pull

                if pull >= 88 { refreshArmed = true }
                if pull == 0, refreshArmed {
                    refreshArmed = false
                    onRefresh()
                }
            }
        #else
        content
        #endif
    }
}

struct ContentView: View {
    @StateObject private var library = MovieLibrary()
    @ObservedObject private var settings: AppSettings
    @State private var selectedTab: LibraryTab = .all
    @State private var searchText = ""
    @State private var selectedDecade: Int?
    @State private var selectedDecadeIsOpenEnded = false
    @State private var selectedGenreID: Int?
    @State private var selectedCountryCode: String?
    @State private var watchlistSort: WatchlistSort = .recent
    @State private var watchedSort: WatchedSort = .newest
    @State private var activeSheet: AppSheet?
    @State private var catalogIsAtTop = true
    @State private var catalogPullDistance: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    init() {
        _settings = ObservedObject(wrappedValue: AppSettings.shared)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let preview = library.featuredMovie, activeSheet == nil {
                FeaturedPreviewBanner(
                    movie: preview,
                    onOpen: { activeSheet = .filmOfDay(preview) },
                    onWatched: { activeSheet = .watchReview(preview) },
                    onDismiss: library.dismissFeatured
                )
            }
            tabPicker
            searchField

            if let error = library.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FilmPalette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FilmPalette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selectedTab != .watched { generatorFooter }
        }
        .modifier(WindowSizing())
        .preferredColorScheme(.light)
        .task {
            if library.hasToken {
                await library.loadNextPage()
                await library.loadMovieGenres()
                await library.loadMovieCountries()
            } else {
                activeSheet = .tokenSetup
            }
        }
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await library.searchMovies(query: query)
        }
        .onChange(of: selectedTab) { _, _ in
            searchText = ""
            isSearchFocused = false
            selectedDecade = nil
            selectedDecadeIsOpenEnded = false
            selectedGenreID = nil
            selectedCountryCode = nil
            library.clearFilterAvailability()
            library.decadeResults = []
        }
        .onChange(of: settings.language) { _, _ in
            Task {
                await library.applyLanguageChange()
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if selectedDecade != nil || selectedGenreID != nil || selectedCountryCode != nil {
                    await loadFilteredCatalog(refresh: true)
                }
                if !query.isEmpty {
                    await library.searchMovies(query: query)
                }
                if case .movieDetails(let movie, let fromWatchlist) = activeSheet {
                    if let localized = await library.fetchLocalizedMovie(id: movie.id) {
                        activeSheet = .movieDetails(localized, fromWatchlist: fromWatchlist)
                    }
                } else if case .filmOfDay(let movie) = activeSheet {
                    if let localized = await library.fetchLocalizedMovie(id: movie.id) {
                        activeSheet = .filmOfDay(localized)
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .tokenSetup:
                TokenSetupView { token in library.saveToken(token) }
                    .presentationDetents([.medium])
            case .filmOfDay(let movie):
                FilmOfDayModal(
                    movie: movie,
                    contentLanguage: settings.language.rawValue,
                    loadDetails: { await library.loadMovieDetails(id: movie.id) },
                    loadCollection: { await library.loadCollectionMovies(id: $0) },
                    onPromote: {
                        library.promoteToWatchlist(movie)
                        activeSheet = nil
                    },
                    onOpenMovie: { related in
                        activeSheet = .movieDetails(related, fromWatchlist: false)
                    }
                )
                .id(movie.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .movieDetails(let movie, let fromWatchlist):
                FilmOfDayModal(
                    movie: movie,
                    contentLanguage: settings.language.rawValue,
                    loadDetails: { await library.loadMovieDetails(id: movie.id) },
                    loadProviders: fromWatchlist ? { await library.loadWatchProviders(id: movie.id) } : nil,
                    loadCollection: { await library.loadCollectionMovies(id: $0) },
                    onPromote: {},
                    isFilmOfDay: false,
                    onClose: { activeSheet = nil },
                    onOpenMovie: { related in
                        activeSheet = .movieDetails(related, fromWatchlist: false)
                    },
                    onAddToWatchlist: fromWatchlist ? nil : {
                        library.addToWatchlist(movie)
                        activeSheet = nil
                    },
                    onMarkWatched: fromWatchlist ? {
                        activeSheet = .watchReview(movie)
                    } : nil,
                    isInWatchlist: library.watchlist.contains { $0.id == movie.id }
                        || library.watched.contains { $0.id == movie.id }
                )
                .id(movie.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .watchReview(let movie):
                WatchReviewModal(
                    movie: movie,
                    onConfirm: { rating, notes in
                        library.markWatched(movie, rating: rating, notes: notes)
                        activeSheet = nil
                    },
                    onCancel: { activeSheet = nil }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FilmPalette.accent)
                .frame(width: 22)
            TextField(
                "Cerca un film, un regista...",
                text: $searchText,
                prompt: Text("Cerca un film, un regista...").foregroundColor(FilmPalette.muted)
            )
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(FilmPalette.ink)
                .tint(FilmPalette.accent)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FilmPalette.muted)
                        .frame(width: 28, height: 28)
                        .background(FilmPalette.line.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella ricerca")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
            .stroke(isSearchFocused ? FilmPalette.accent.opacity(0.8) : FilmPalette.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.16), value: isSearchFocused)
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases) { tab in
                Button { withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab } } label: {
                    VStack(spacing: 9) {
                        HStack(spacing: 6) {
                            Text(tab.rawValue).font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            if tab != .all {
                                Text(String(count(for: tab)))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(selectedTab == tab ? FilmPalette.accent : FilmPalette.muted)
                            }
                        }
                        Rectangle().fill(selectedTab == tab ? FilmPalette.accent : .clear).frame(height: 2)
                    }
                    .foregroundStyle(selectedTab == tab ? FilmPalette.paper : FilmPalette.mutedOnDark)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            settingsMenu
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }

    private var settingsMenu: some View {
        Menu {
            Section("Lingua") {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        settings.language = language
                    } label: {
                        if settings.language == language {
                            Label("\(language.flag)  \(language.nativeName)", systemImage: "checkmark")
                        } else {
                            Text("\(language.flag)  \(language.nativeName)")
                        }
                    }
                }
            }
        } label: {
            Text(settings.language.flag)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .padding(.bottom, 11)
        .accessibilityLabel("Lingua: \(settings.language.nativeName)")
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .all:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasDiscoverFilters = selectedDecade != nil || selectedGenreID != nil || selectedCountryCode != nil
            let sourceResults = !hasDiscoverFilters
                ? (query.isEmpty ? library.movies : library.searchResults)
                : library.decadeResults
            let availableDecades = decades()
            let results = sourceResults
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            decadeFilterMenu(decades: availableDecades)
                            genreFilterMenu
                            countryFilterMenu
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                    }
                    .defaultScrollAnchor(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .zIndex(1)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            LazyVGrid(columns: catalogColumns(for: geometry.size.width), alignment: .leading, spacing: 22) {
                                ForEach(results) { movie in
                                    CatalogMovieTile(
                                        movie: movie,
                                        isSaved: library.watchlist.contains { $0.id == movie.id },
                                        isWatched: library.watched.contains { $0.id == movie.id },
                                        onAdd: { library.addToWatchlist(movie) },
                                        onOpen: { activeSheet = .movieDetails(movie, fromWatchlist: false) }
                                    )
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 14)
                            .padding(.bottom, 22)

                            if !sourceResults.isEmpty {
                                Color.clear
                                    .frame(height: 1)
                                    .id(sourceResults.count)
                                    .onAppear {
                                        Task {
                                            if hasDiscoverFilters {
                                                await loadFilteredCatalog(loadMore: true)
                                            } else if query.isEmpty {
                                                await library.loadNextPage()
                                            } else {
                                                await library.searchMovies(query: query, loadMore: true)
                                            }
                                        }
                                    }
                            }

                            loadingState(isEmpty: results.isEmpty && !library.isSearching && !library.isLoadingDecade)
                        }
                    }
                    .refreshable {
                        await refreshCatalogClearingFilters()
                    }
                    .modifier(DesktopPullToRefresh(
                        isAtTop: $catalogIsAtTop,
                        pullDistance: $catalogPullDistance,
                        onRefresh: {
                            Task { await refreshCatalogClearingFilters() }
                        }
                    ))
                    .overlay(alignment: .top) {
                        if library.isRefreshing || catalogPullDistance > 16 {
                            ProgressView()
                                .padding(.top, 12)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.16), value: library.isRefreshing)
                    .animation(.easeOut(duration: 0.12), value: catalogPullDistance > 16)
                }
            }
        case .watchlist:
            let results = ordered(library.watchlist.filter { matches($0) })
            ScrollView {
                if !results.isEmpty {
                    HStack {
                        sectionLabel("PROSSIME VISIONI", count: results.count)
                        Spacer()
                        watchlistSortMenu
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    LazyVStack(spacing: 10) {
                        ForEach(results) { movie in
                            SavedMovieRow(movie: movie) {
                                activeSheet = .watchReview(movie)
                            } onOpen: {
                                activeSheet = .movieDetails(movie, fromWatchlist: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                } else {
                    emptyState(icon: "bookmark", title: "La lista è tutta tua", subtitle: "Aggiungi un film da Tutti o genera una prossima visione.")
                }
            }
        case .watched:
            let results = orderedWatched(library.watched.filter { matches($0.movie) })
            ScrollView {
                if !results.isEmpty {
                    HStack {
                        sectionLabel("IL TUO ARCHIVIO", count: results.count)
                        Spacer()
                        watchedSortMenu
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 21)
                    LazyVStack(spacing: 10) {
                        ForEach(results) { item in
                            WatchedMovieRow(
                                item: item,
                                onOpen: { activeSheet = .movieDetails(item.movie, fromWatchlist: false) },
                                onRating: { rating in
                                    library.updateReview(for: item.id, rating: rating)
                                },
                                onNotes: { notes in
                                    library.updateReview(for: item.id, notes: notes)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 24)
                } else {
                    emptyState(icon: "ticket", title: "Ancora nessun finale", subtitle: "I film che segni come visti compariranno qui, pronti per la tua recensione.")
                }
            }
        }
    }

    private var generatorFooter: some View {
        HStack {
            Spacer()
            Button(action: generateFilmOfToday) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    Text("Film di oggi").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(FilmPalette.ink)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityHint(selectedTab == .all ? "Estrae un film casuale dal catalogo" : "Estrae un film casuale dalla lista Da vedere")
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(FilmPalette.canvas)
    }

    private var watchlistSortMenu: some View {
        Menu {
            ForEach(WatchlistSort.allCases) { option in
                Button {
                    watchlistSort = option
                } label: {
                    if option == watchlistSort {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            sortMenuLabel(watchlistSort.rawValue)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Ordina i film da vedere")
    }

    private func decadeFilterMenu(decades: [Int]) -> some View {
        Menu {
            Button {
                selectDecade(nil, openEnded: false)
            } label: {
                filterMenuLabel(title: "Tutte le epoche", selected: selectedDecade == nil)
            }
            ForEach(filteredDecades(from: decades), id: \.self) { decade in
                let isLatestDecade = decade == decades.last
                Button {
                    selectDecade(decade, openEnded: isLatestDecade)
                } label: {
                    filterMenuLabel(
                        title: decadeLabel(decade, openEnded: isLatestDecade),
                        selected: selectedDecade == decade && selectedDecadeIsOpenEnded == isLatestDecade
                    )
                }
            }
            if library.isLoadingDecadeOptions {
                ProgressView()
            } else if filteredDecades(from: decades).isEmpty, selectedGenreID != nil || selectedCountryCode != nil {
                Text("Nessuna epoca disponibile")
            }
        } label: {
            filterPill(
                icon: "calendar",
                title: selectedDecade.map { decadeLabel($0, openEnded: selectedDecadeIsOpenEnded) } ?? "Tutte le epoche"
            )
        }
        .menuOrder(.fixed)
        .menuActionDismissBehavior(.automatic)
        .onAppear {
            Task { await refreshFilterAvailability(includeCountries: false) }
        }
        .accessibilityLabel("Filtra i film per decennio")
    }

    private var genreFilterMenu: some View {
        Menu {
            Button {
                selectGenre(nil)
            } label: {
                filterMenuLabel(title: "Tutti i generi", selected: selectedGenreID == nil)
            }
            ForEach(filteredGenres, id: \.id) { genre in
                Button {
                    selectGenre(genre.id)
                } label: {
                    filterMenuLabel(title: genre.name, selected: selectedGenreID == genre.id)
                }
            }
            if library.isLoadingGenreOptions {
                ProgressView()
            } else if filteredGenres.isEmpty, selectedDecade != nil || selectedCountryCode != nil {
                Text("Nessun genere disponibile")
            }
        } label: {
            filterPill(
                icon: "theatermasks",
                title: library.movieGenres.first(where: { $0.id == selectedGenreID })?.name ?? "Tutti i generi"
            )
        }
        .menuOrder(.fixed)
        .onAppear {
            Task { await refreshFilterAvailability(includeCountries: false) }
        }
        .accessibilityLabel("Filtra i film per genere")
    }

    private var countryFilterMenu: some View {
        Menu {
            Button {
                selectCountry(nil)
            } label: {
                filterMenuLabel(title: "Tutti i paesi", selected: selectedCountryCode == nil)
            }
            ForEach(filteredCountries) { country in
                Button {
                    selectCountry(country.code)
                } label: {
                    filterMenuLabel(
                        title: CountryNames.name(for: country.code),
                        selected: selectedCountryCode == country.code
                    )
                }
            }
            if library.isLoadingCountries || library.isLoadingCountryOptions {
                ProgressView()
            } else if filteredCountries.isEmpty, selectedDecade != nil || selectedGenreID != nil {
                Text("Nessun paese disponibile")
            } else if library.movieCountries.isEmpty {
                Text("Nessun paese disponibile")
            }
        } label: {
            filterPill(
                icon: "globe",
                title: selectedCountryCode.map(CountryNames.name(for:)) ?? "Tutti i paesi"
            )
        }
        .menuOrder(.fixed)
        .onAppear {
            Task { await refreshFilterAvailability(includeCountries: true) }
        }
        .accessibilityLabel("Filtra i film per paese")
    }

    @ViewBuilder
    private func filterMenuLabel(title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(verbatim: title)
        }
    }

    private func refreshCatalogClearingFilters() async {
        selectedDecade = nil
        selectedDecadeIsOpenEnded = false
        selectedGenreID = nil
        selectedCountryCode = nil
        library.clearFilterAvailability()
        library.decadeResults = []
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        await library.refreshMovies(query: query)
    }

    private func filterPill(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(FilmPalette.ink)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(FilmPalette.paper, in: RoundedRectangle(cornerRadius: 9))
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private enum FilterDimension {
        case decade, genre, country
    }

    private func selectDecade(_ decade: Int?, openEnded: Bool) {
        searchText = ""
        selectedDecade = decade
        selectedDecadeIsOpenEnded = openEnded
        Task { await applyFilterChange(changed: .decade) }
    }

    private func selectGenre(_ genreID: Int?) {
        searchText = ""
        selectedGenreID = genreID
        Task { await applyFilterChange(changed: .genre) }
    }

    private func selectCountry(_ countryCode: String?) {
        searchText = ""
        selectedCountryCode = countryCode
        Task { await applyFilterChange(changed: .country) }
    }

    /// Mantiene il filtro appena scelto, toglie gli altri incompatibili, poi aggiorna catalogo e select.
    private func applyFilterChange(changed: FilterDimension) async {
        switch changed {
        case .decade:
            if let genreID = selectedGenreID {
                let ok = await library.filtersStillMatch(
                    decade: selectedDecade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: genreID,
                    countryCode: selectedCountryCode
                )
                if !ok { selectedGenreID = nil }
            }
            if let countryCode = selectedCountryCode {
                let ok = await library.filtersStillMatch(
                    decade: selectedDecade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: selectedGenreID,
                    countryCode: countryCode
                )
                if !ok { selectedCountryCode = nil }
            }
        case .genre:
            if let decade = selectedDecade {
                let ok = await library.filtersStillMatch(
                    decade: decade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: selectedGenreID,
                    countryCode: selectedCountryCode
                )
                if !ok {
                    selectedDecade = nil
                    selectedDecadeIsOpenEnded = false
                }
            }
            if let countryCode = selectedCountryCode {
                let ok = await library.filtersStillMatch(
                    decade: selectedDecade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: selectedGenreID,
                    countryCode: countryCode
                )
                if !ok { selectedCountryCode = nil }
            }
        case .country:
            if let decade = selectedDecade {
                let ok = await library.filtersStillMatch(
                    decade: decade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: selectedGenreID,
                    countryCode: selectedCountryCode
                )
                if !ok {
                    selectedDecade = nil
                    selectedDecadeIsOpenEnded = false
                }
            }
            if let genreID = selectedGenreID {
                let ok = await library.filtersStillMatch(
                    decade: selectedDecade,
                    openEnded: selectedDecadeIsOpenEnded,
                    genreID: genreID,
                    countryCode: selectedCountryCode
                )
                if !ok { selectedGenreID = nil }
            }
        }

        await loadFilteredCatalog(refresh: true)
        // Epoche/generi subito; paesi in background (molte più richieste).
        await refreshFilterAvailability(includeCountries: false)
        let decade = selectedDecade
        let openEnded = selectedDecadeIsOpenEnded
        let genreID = selectedGenreID
        Task {
            await library.loadAvailableCountries(
                forDecade: decade,
                openEnded: openEnded,
                genreID: genreID
            )
        }
    }

    private func refreshFilterAvailability(includeCountries: Bool) async {
        async let decadesTask: Void = library.loadAvailableDecades(
            forGenre: selectedGenreID,
            countryCode: selectedCountryCode
        )
        async let genresTask: Void = library.loadAvailableGenres(
            forDecade: selectedDecade,
            openEnded: selectedDecadeIsOpenEnded,
            countryCode: selectedCountryCode
        )
        if includeCountries {
            let decade = selectedDecade
            let openEnded = selectedDecadeIsOpenEnded
            let genreID = selectedGenreID
            Task {
                await library.loadAvailableCountries(
                    forDecade: decade,
                    openEnded: openEnded,
                    genreID: genreID
                )
            }
        }
        _ = await (decadesTask, genresTask)
    }

    private func decades() -> [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        let latestDecade = (currentYear / 10) * 10
        return Array(stride(from: 1890, through: latestDecade, by: 10))
    }

    private func filteredDecades(from decades: [Int]) -> [Int] {
        guard let available = library.availableDecadeIDs else { return decades }
        return decades.filter { available.contains($0) }
    }

    private var filteredGenres: [MovieGenre] {
        guard let available = library.availableGenreIDs else { return library.movieGenres }
        return library.movieGenres.filter { available.contains($0.id) }
    }

    private var filteredCountries: [MovieCountry] {
        guard let available = library.availableCountryCodes else { return library.movieCountries }
        return library.movieCountries.filter { available.contains($0.code) }
    }

    private func loadFilteredCatalog(loadMore: Bool = false, refresh: Bool = false) async {
        guard selectedDecade != nil || selectedGenreID != nil || selectedCountryCode != nil else {
            library.decadeResults = []
            if !loadMore, library.movies.isEmpty {
                await library.loadNextPage(refresh: true)
            }
            return
        }
        await library.loadMovies(
            forDecade: selectedDecade,
            genreID: selectedGenreID,
            countryCode: selectedCountryCode,
            openEnded: selectedDecadeIsOpenEnded,
            loadMore: loadMore,
            refresh: refresh
        )
    }

    private func decadeLabel(_ decade: Int, openEnded: Bool) -> String {
        openEnded ? "\(decade)+" : "\(decade)-\(decade + 10)"
    }

    private var watchedSortMenu: some View {
        Menu {
            ForEach(WatchedSort.allCases) { option in
                Button {
                    watchedSort = option
                } label: {
                    if option == watchedSort {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            sortMenuLabel(watchedSort.rawValue)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Ordina i film visti")
    }

    private func sortMenuLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(FilmPalette.ink)
        .padding(.horizontal, 14)
        .frame(minWidth: 132)
        .frame(height: 36)
        .background(FilmPalette.paper, in: RoundedRectangle(cornerRadius: 9))
        .padding(4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func matches(_ movie: Movie) -> Bool {
        searchText.isEmpty || movie.title.localizedCaseInsensitiveContains(searchText)
    }

    private func generateFilmOfToday() {
        library.generate(from: selectedTab)
        if let movie = library.featuredMovie {
            activeSheet = .filmOfDay(movie)
        }
    }

    private func catalogColumns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 14
        let minimumColumnWidth: CGFloat = 170
        let columnCount = min(4, max(2, Int((width + spacing) / (minimumColumnWidth + spacing))))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    private func ordered(_ movies: [Movie]) -> [Movie] {
        switch watchlistSort {
        case .recent:
            movies
        case .newestYear:
            movies.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldestYear:
            movies.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        }
    }

    private func orderedWatched(_ movies: [WatchedMovie]) -> [WatchedMovie] {
        switch watchedSort {
        case .newest:
            movies.sorted { $0.watchedAt > $1.watchedAt }
        case .oldest:
            movies.sorted { $0.watchedAt < $1.watchedAt }
        case .highestRated:
            movies.sorted { $0.rating > $1.rating }
        case .lowestRated:
            movies.sorted { $0.rating < $1.rating }
        }
    }

    private func count(for tab: LibraryTab) -> Int {
        switch tab {
        case .all: library.movies.count
        case .watchlist: library.watchlist.count
        case .watched: library.watched.count
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(FilmPalette.mutedOnDark)
            Text(String(count)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(FilmPalette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func loadingState(isEmpty: Bool) -> some View {
        if library.isLoading || library.isSearching || library.isLoadingDecade {
            ProgressView().tint(FilmPalette.accent).padding(.vertical, 18)
        } else if isEmpty && library.hasToken {
            emptyState(icon: "film", title: "Nessun film trovato", subtitle: "Riprova tra poco o controlla la connessione.")
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(FilmPalette.accent)
            Text(title).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(FilmPalette.paper)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(FilmPalette.mutedOnDark).multilineTextAlignment(.center).frame(maxWidth: 270)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 54)
    }
}

private struct CatalogMovieTile: View {
    let movie: Movie
    let isSaved: Bool
    let isWatched: Bool
    let onAdd: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    MoviePoster(movie: movie)
                        .aspectRatio(0.69, contentMode: .fit)
                        .overlay(alignment: .topTrailing) {
                            if isWatched {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(FilmPalette.ink).padding(8).background(FilmPalette.softGreen, in: Circle()).padding(8)
                            }
                        }
                    Text(movie.title).font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(FilmPalette.paper).lineLimit(2).frame(height: 36, alignment: .topLeading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mostra dettagli di \(movie.title)")
            HStack(spacing: 6) {
                Text(movie.year.map(String.init) ?? "—").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(FilmPalette.mutedOnDark)
                Spacer(minLength: 2)
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: isSaved || isWatched ? "checkmark" : "plus")
                        Text(isSaved || isWatched ? "In lista" : "Da vedere")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSaved || isWatched ? FilmPalette.ink : FilmPalette.paper)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(isSaved || isWatched ? FilmPalette.softGreen : FilmPalette.ink, in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .disabled(isSaved || isWatched)
                .accessibilityLabel(isSaved || isWatched ? "Già nella tua libreria" : "Aggiungi ai film da vedere")
            }
        }
    }
}

private struct MoviePoster: View {
    let movie: Movie

    var body: some View {
        AsyncImage(url: movie.posterURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [FilmPalette.ink.opacity(0.86), FilmPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "film").font(.system(size: 28, weight: .light)).foregroundStyle(FilmPalette.accent)
                }
            }
        }
        .frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct SavedMovieRow: View {
    let movie: Movie
    let onWatched: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onOpen) {
                HStack(spacing: 13) {
                    MoviePoster(movie: movie).frame(width: 66, height: 94)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(movie.title).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(FilmPalette.paper).lineLimit(2)
                        Text(movie.year.map(String.init) ?? "Anno non disponibile")
                            .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(FilmPalette.mutedOnDark)
                        if movie.voteAverage > 0 {
                            Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(FilmPalette.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mostra dettagli di \(movie.title)")
            Spacer(minLength: 0)
            Button(action: onWatched) {
                Label("Visto", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FilmPalette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Segna \(movie.title) come visto")
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(FilmPalette.listSurface, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct WatchedMovieRow: View {
    let item: WatchedMovie
    let onOpen: () -> Void
    let onRating: (Int) -> Void
    let onNotes: (String) -> Void
    @State private var isReviewOpen = false
    @State private var draftNotes = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                MoviePoster(movie: item.movie).frame(width: 61, height: 88)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apri scheda di \(item.movie.title)")

            VStack(alignment: .leading, spacing: 7) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.movie.title).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(FilmPalette.paper).lineLimit(2)
                        Text(item.movie.year.map(String.init) ?? "Anno non disponibile")
                            .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(FilmPalette.mutedOnDark)
                        Text("Visto il \(item.watchedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(FilmPalette.mutedOnDark)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apri scheda di \(item.movie.title)")

                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { star in
                        Button { onRating(star) } label: {
                            Image(systemName: star <= item.rating ? "star.fill" : "star")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(star <= item.rating ? FilmPalette.accent : FilmPalette.line)
                                .frame(width: 23, height: 23)
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(star) stelle")
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if isReviewOpen {
                                isReviewOpen = false
                            } else {
                                draftNotes = item.notes
                                isReviewOpen = true
                            }
                        }
                    } label: {
                        Image(systemName: isReviewOpen || !item.notes.isEmpty ? "message.fill" : "message")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isReviewOpen || !item.notes.isEmpty ? FilmPalette.accent : FilmPalette.paper)
                            .frame(width: 28, height: 23)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isReviewOpen ? "Chiudi recensione" : (item.notes.isEmpty ? "Scrivi una recensione" : "Apri recensione"))
                }
                if isReviewOpen {
                    TextEditor(text: $draftNotes)
                        .font(.system(size: 12))
                        .foregroundStyle(FilmPalette.paper)
                        .tint(FilmPalette.accent)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 58, maxHeight: 90)
                        .padding(7)
                        .background(FilmPalette.ink.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(alignment: .topLeading) {
                            if draftNotes.isEmpty {
                                Text("Scrivi una nota o una recensione…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FilmPalette.mutedOnDark.opacity(0.75))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 15)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel("Recensione di \(item.movie.title)")
                        .onChange(of: draftNotes) { _, newValue in
                            onNotes(newValue)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(FilmPalette.listSurface, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct FeaturedPreviewBanner: View {
    let movie: Movie
    let onOpen: () -> Void
    let onWatched: () -> Void
    let onDismiss: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            HStack(spacing: 13) {
                Button(action: onOpen) {
                    HStack(spacing: 13) {
                        MoviePoster(movie: movie)
                            .frame(width: 58, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("DA VEDERE OGGI")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(FilmPalette.accent)
                            Text(movie.title)
                                .font(.system(size: 19, weight: .medium, design: .serif))
                                .foregroundStyle(FilmPalette.paper)
                                .lineLimit(1)
                            Text(movie.year.map(String.init) ?? "Anno sconosciuto")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(FilmPalette.paper.opacity(0.65))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apri scheda di \(movie.title)")

                Button(action: onWatched) {
                    Label("Visto", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FilmPalette.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FilmPalette.paper.opacity(0.65))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi anteprima")
            }

            if isExpanded {
                Text(movie.overview.isEmpty ? "Nessuna sinossi disponibile." : movie.overview)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(FilmPalette.paper.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 71)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FilmPalette.paper.opacity(0.78))
                        .frame(width: 40, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Comprimi anteprima" : "Espandi anteprima")
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(FilmPalette.ink)
    }
}

private struct FilmOfDayModal: View {
    let movie: Movie
    var contentLanguage: String = AppLanguage.italian.rawValue
    let loadDetails: () async -> MovieDetails?
    var loadProviders: (() async -> MovieWatchAvailability?)? = nil
    var loadCollection: (Int) async -> [Movie] = { _ in [] }
    let onPromote: () -> Void
    var isFilmOfDay = true
    var onClose: (() -> Void)? = nil
    var onOpenMovie: ((Movie) -> Void)? = nil
    var onAddToWatchlist: (() -> Void)? = nil
    var onMarkWatched: (() -> Void)? = nil
    var isInWatchlist = false
    @State private var movieDetails: MovieDetails?
    @State private var watchAvailability: MovieWatchAvailability?
    @State private var collectionMovies: [Movie] = []
    @State private var isLoadingDetails = true
    @State private var isLoadingProviders = false
    @State private var isLoadingCollection = false
    @State private var showingProviders = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 620
            let pad: CGFloat = wide ? 48 : 24
            let contentWidth = max(0, geometry.size.width - pad * 2)
            let posterWidth = wide ? min(230, contentWidth * 0.28) : min(contentWidth * 0.42, 180)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if wide {
                        HStack(alignment: .top, spacing: 34) {
                            poster(width: posterWidth)
                            detailsColumn
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            poster(width: posterWidth)
                                .frame(maxWidth: .infinity)
                            detailsColumn
                        }
                    }
                    actionRow
                    if hasSupplementaryContent {
                        supplementaryContent(width: contentWidth)
                            .padding(.bottom, 8)
                    }
                }
                .padding(pad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(FilmPalette.ink)
        }
        .background(FilmPalette.ink.ignoresSafeArea())
        .task(id: "\(movie.id)-\(contentLanguage)") {
            isLoadingDetails = true
            isLoadingCollection = false
            collectionMovies = []
            showingProviders = false
            let details = await loadDetails()
            movieDetails = details
            if let loadProviders {
                if let providers = details?.watchProviders {
                    watchAvailability = providers.availability()
                } else {
                    isLoadingProviders = true
                    watchAvailability = await loadProviders()
                    isLoadingProviders = false
                }
            }
            isLoadingDetails = false
            if let collectionID = details?.belongsToCollection?.id {
                isLoadingCollection = true
                collectionMovies = await loadCollection(collectionID)
                isLoadingCollection = false
            }
        }
        #if os(macOS)
        .frame(width: 900, height: 680)
        #endif
    }

    private func poster(width: CGFloat) -> some View {
        MoviePoster(movie: movie)
            .frame(width: width, height: width / 0.69)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
    }

    private var detailsColumn: some View {
        VStack(alignment: .leading, spacing: 17) {
            detailsHeader
            overviewText
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var hasSupplementaryContent: Bool {
        let hasRelated = movieDetails?.belongsToCollection != nil && (isLoadingCollection || !relatedMovies.isEmpty)
        let hasCast = !(movieDetails?.actingCast.isEmpty ?? true)
        let hasTrailer = movieDetails?.trailer(preferredLanguage: contentLanguage) != nil
        return hasRelated || hasCast || hasTrailer
    }

    private var detailsHeader: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Text(isFilmOfDay ? "FILM DI OGGI" : "DETTAGLI DEL FILM")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(FilmPalette.accent)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FilmPalette.paper.opacity(0.78))
                            .frame(width: 34, height: 34)
                            .background(FilmPalette.paper.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chiudi dettagli film")
                }
            }
            Text(movie.title)
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundStyle(FilmPalette.paper)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(movie.year.map(String.init) ?? "Anno sconosciuto")
                Text("·")
                Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                    .foregroundStyle(FilmPalette.accent)
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(FilmPalette.paper.opacity(0.66))
            if let movieDetails {
                let metadata = [
                    movieDetails.genres.map(\.name).joined(separator: " · "),
                    movieDetails.runtime.map { "\($0) min" },
                    movieDetails.status,
                    movieDetails.originFlags
                ].compactMap { $0 }.filter { !$0.isEmpty }
                if !metadata.isEmpty {
                    Text(metadata.joined(separator: "  ·  "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FilmPalette.paper.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tagline = movieDetails.tagline, !tagline.isEmpty {
                    Text("\u{201C}\(tagline)\u{201D}")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(FilmPalette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isLoadingDetails {
                ProgressView().tint(FilmPalette.accent).controlSize(.small)
            }
            Rectangle()
                .fill(FilmPalette.paper.opacity(0.17))
                .frame(height: 1)
        }
    }

    private var overviewText: some View {
        Text(movie.overview.isEmpty ? "Nessuna sinossi disponibile." : movie.overview)
            .font(.system(size: 15))
            .lineSpacing(5)
            .foregroundStyle(FilmPalette.paper.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
                Spacer()
                if isFilmOfDay {
                    Button(action: onPromote) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FilmPalette.ink)
                            .frame(width: 52, height: 46)
                            .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sposta in cima a Da vedere e mostra anteprima")
                } else if onMarkWatched != nil {
                    if loadProviders != nil {
                        watchProvidersButton
                    }
                    Button {
                        onMarkWatched?()
                    } label: {
                        Label("Visto", systemImage: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FilmPalette.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                            .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Segna \(movie.title) come visto")
                } else if let onAddToWatchlist {
                    Button(action: onAddToWatchlist) {
                        Label(isInWatchlist ? "In lista" : "Da vedere", systemImage: isInWatchlist ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FilmPalette.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                            .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(isInWatchlist)
                    .accessibilityLabel(isInWatchlist ? "Film già nella lista Da vedere" : "Aggiungi ai film da vedere")
                }
            }
        }

    private func supplementaryContent(width: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 18) {
            if movieDetails?.belongsToCollection != nil, isLoadingCollection || !relatedMovies.isEmpty {
                relatedMoviesSection
            }
            if let movieDetails {
                let actors = movieDetails.actingCast
                let trailer = movieDetails.trailer(preferredLanguage: contentLanguage)
                if !actors.isEmpty || trailer != nil {
                    Rectangle()
                        .fill(FilmPalette.paper.opacity(0.17))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                    if !actors.isEmpty {
                        VStack(alignment: .center, spacing: 10) {
                            Text("Cast")
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .foregroundStyle(FilmPalette.paper)
                                .frame(maxWidth: .infinity)
                            centeredHorizontalRow(height: 136) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(actors) { actor in
                                        VStack(spacing: 6) {
                                            AsyncImage(url: actor.profileURL) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    ZStack {
                                                        FilmPalette.paper.opacity(0.08)
                                                        Image(systemName: "person")
                                                            .font(.system(size: 18, weight: .light))
                                                            .foregroundStyle(FilmPalette.paper.opacity(0.7))
                                                    }
                                                }
                                            }
                                            .frame(width: 64, height: 64)
                                            .clipShape(Circle())
                                            Text(actor.name)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(FilmPalette.paper)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                            Text(actor.character)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(FilmPalette.mutedOnDark)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(width: 84, alignment: .top)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("\(actor.name), \(actor.character)")
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let trailer {
                        TrailerPlayer(videoID: trailer.key)
                            .frame(width: width, height: width * 9 / 16)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("Trailer di \(movie.title)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func centeredHorizontalRow<Content: View>(height: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                content()
                    .frame(minWidth: proxy.size.width)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var relatedMovies: [Movie] {
        collectionMovies.filter { $0.id != movie.id }
    }

    private var relatedMoviesSection: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Vedi anche:")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(FilmPalette.paper)
                .frame(maxWidth: .infinity)
            if isLoadingCollection {
                ProgressView()
                    .tint(FilmPalette.accent)
                    .controlSize(.small)
            } else {
                centeredHorizontalRow(height: 142) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(relatedMovies) { related in
                            Button {
                                onOpenMovie?(related)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    MoviePoster(movie: related)
                                        .frame(width: 72, height: 104)
                                    Text(related.title)
                                        .font(.system(size: 11, weight: .medium, design: .serif))
                                        .foregroundStyle(FilmPalette.paper)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: 72, height: 28, alignment: .topLeading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Apri \(related.title)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var watchProvidersButton: some View {
        Button {
            showingProviders.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.tv")
                    .font(.system(size: 13, weight: .semibold))
                Text("Disponibile su")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(FilmPalette.ink)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(FilmPalette.paper, in: RoundedRectangle(cornerRadius: 4))
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .compactPicker(
            isPresented: $showingProviders,
            macWidth: 280,
            macHeight: providersMenuHeight(for: watchAvailability?.offers.groups ?? [])
        ) {
            watchProvidersMenu
        }
        .accessibilityLabel("Mostra le piattaforme dove è disponibile \(movie.title)")
    }

    private var watchProvidersMenu: some View {
        let groups = watchAvailability?.offers.groups ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let watchAvailability {
                    Text(CountryNames.name(for: watchAvailability.regionCode).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(FilmPalette.muted)
                }
                if isLoadingProviders {
                    ProgressView()
                        .tint(FilmPalette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if watchAvailability == nil {
                    Text("Impossibile caricare le piattaforme")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FilmPalette.ink)
                } else if groups.isEmpty {
                    Text("Nessuna piattaforma disponibile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FilmPalette.ink)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(FilmPalette.muted)
                            ForEach(group.providers) { provider in
                                HStack(spacing: 10) {
                                    AsyncImage(url: provider.logoURL) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFill()
                                        } else {
                                            FilmPalette.line
                                        }
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(provider.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(FilmPalette.ink)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                Text("Fonte: JustWatch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FilmPalette.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func providersMenuHeight(for groups: [WatchProviderGroup]) -> CGFloat {
        if isLoadingProviders || watchAvailability == nil || groups.isEmpty { return 132 }
        let rows = groups.reduce(0) { $0 + $1.providers.count }
        return min(CGFloat(rows) * 36 + CGFloat(groups.count) * 28 + 72, 380)
    }
}

private struct TokenSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var showToken = false
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Colleghiamo TMDB").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundStyle(FilmPalette.ink)
                    Text("Il token di lettura resta nel portachiavi del dispositivo.").font(.system(size: 13)).foregroundStyle(FilmPalette.muted)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(FilmPalette.muted)
                        .frame(width: 34, height: 34).background(FilmPalette.canvas, in: Circle())
                }
            }
            HStack(spacing: 9) {
                Group {
                    if showToken { TextField("Bearer token TMDB", text: $token) }
                    else { SecureField("Bearer token TMDB", text: $token) }
                }
                .autocorrectionDisabled()
                Button { showToken.toggle() } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye").foregroundStyle(FilmPalette.muted)
                }
                .accessibilityLabel(showToken ? "Nascondi token" : "Mostra token")
            }
            .font(.system(size: 13)).padding(.horizontal, 13).frame(height: 48)
            .background(FilmPalette.canvas, in: RoundedRectangle(cornerRadius: 6))
            Button {
                onSave(token)
                dismiss()
            } label: {
                Text("Salva e carica i film").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(FilmPalette.ink, in: RoundedRectangle(cornerRadius: 6))
            }
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            Spacer(minLength: 0)
        }
        .padding(24).padding(.top, 8).background { Color.white.ignoresSafeArea() }
    }
}

private struct WatchReviewModal: View {
    let movie: Movie
    let onConfirm: (Int, String) -> Void
    let onCancel: () -> Void
    @State private var rating = 0
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("LA TUA RECENSIONE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(FilmPalette.accent)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FilmPalette.paper.opacity(0.78))
                        .frame(width: 34, height: 34)
                        .background(FilmPalette.paper.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Annulla")
            }

            HStack(alignment: .top, spacing: 14) {
                MoviePoster(movie: movie)
                    .frame(width: 72, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 6) {
                    Text(movie.title)
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(FilmPalette.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(movie.year.map(String.init) ?? "Anno non disponibile")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(FilmPalette.mutedOnDark)
                    Text("Segna come visto e lascia una valutazione.")
                        .font(.system(size: 13))
                        .foregroundStyle(FilmPalette.paper.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Valutazione")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FilmPalette.mutedOnDark)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Button { rating = star } label: {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(star <= rating ? FilmPalette.accent : FilmPalette.line)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(star) stelle")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commento")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FilmPalette.mutedOnDark)
                TextEditor(text: $notes)
                    .font(.system(size: 14))
                    .foregroundStyle(FilmPalette.paper)
                    .tint(FilmPalette.accent)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 160)
                    .padding(10)
                    .background(FilmPalette.listSurface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Scrivi una recensione (opzionale)…")
                                .font(.system(size: 14))
                                .foregroundStyle(FilmPalette.mutedOnDark.opacity(0.75))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Commento su \(movie.title)")
            }

            Spacer(minLength: 0)

            Button {
                onConfirm(rating, notes.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text("Conferma visto")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FilmPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(FilmPalette.accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Conferma e salva come visto")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FilmPalette.ink.ignoresSafeArea())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
