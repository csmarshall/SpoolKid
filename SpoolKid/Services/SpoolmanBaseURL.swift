//
//  SpoolmanBaseURL.swift
//  SpoolKid
//
//  Purpose: Parses and normalises the Spoolman server address typed by the user
//  and builds endpoint URLs from it, so a base URL that carries a path
//  (https://example.com/spoolman) behaves the same with or without a trailing slash.
//

import Foundation

nonisolated struct SpoolmanBaseURL: Equatable {
    enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case unsupportedScheme(String?)
        case missingHost
        case hasQuery
        case hasFragment
        case hasUserInfo
        case invalid

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter the address of your Spoolman server."
            case .unsupportedScheme:
                return "The server address must start with http:// or https://."
            case .missingHost:
                return "The server address has no host name."
            case .hasQuery:
                return "The server address must not contain a query (anything after ?)."
            case .hasFragment:
                return "The server address must not contain a fragment (anything after #)."
            case .hasUserInfo:
                return "Put the user name and password in the authentication settings, not in the server address."
            case .invalid:
                return "The server address is not a valid URL."
            }
        }
    }

    /// The normalised base: lower-case scheme, no trailing slash, path kept as typed.
    let url: URL

    private let components: URLComponents

    /// Validates `raw` and strips whitespace and trailing slashes. The path is kept.
    init(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }
        guard var components = URLComponents(string: trimmed) else { throw ParseError.invalid }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ParseError.unsupportedScheme(components.scheme)
        }
        guard let host = components.host, !host.isEmpty else { throw ParseError.missingHost }
        guard components.query == nil else { throw ParseError.hasQuery }
        guard components.fragment == nil else { throw ParseError.hasFragment }
        guard components.user == nil, components.password == nil else { throw ParseError.hasUserInfo }

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.scheme = scheme
        components.percentEncodedPath = path

        guard let url = components.url else { throw ParseError.invalid }
        self.url = url
        self.components = components
    }

    /// Appends an already percent-encoded endpoint path ("/api/v1/spool") to the base path.
    /// Returns nil if the result is not a valid URL.
    func endpoint(_ path: String) -> URL? {
        var result = components
        let suffix = path.hasPrefix("/") ? path : "/" + path
        result.percentEncodedPath = components.percentEncodedPath + suffix
        return result.url
    }

    /// True when `other` has the same scheme, host and effective port as the base.
    func isSameOrigin(as other: URL) -> Bool {
        guard let theirs = URLComponents(url: other, resolvingAgainstBaseURL: false),
              let scheme = theirs.scheme?.lowercased(), let host = theirs.host?.lowercased(),
              let ourScheme = components.scheme, let ourHost = components.host?.lowercased() else {
            return false
        }
        return scheme == ourScheme
            && host == ourHost
            && Self.effectivePort(of: theirs) == Self.effectivePort(of: components)
    }

    private static func effectivePort(of components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
