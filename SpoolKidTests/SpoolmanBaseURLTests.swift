//
//  SpoolmanBaseURLTests.swift
//  SpoolKidTests
//
//  Tests for SpoolmanBaseURL: normalisation of the typed server address and
//  endpoint URL building for hosts with and without a port or a sub-path.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanBaseURLTests {
    private static func endpoint(_ base: String, _ path: String = "/api/v1/spool") throws -> String? {
        try SpoolmanBaseURL(base).endpoint(path)?.absoluteString
    }

    // MARK: - Hosts, ports, paths

    @Test(arguments: [
        ("http://192.168.1.10:7912", "http://192.168.1.10:7912/api/v1/spool"),
        ("https://spoolman.example.com", "https://spoolman.example.com/api/v1/spool"),
        ("http://spoolman.local:7912/spoolman", "http://spoolman.local:7912/spoolman/api/v1/spool"),
        ("https://example.com/spoolman", "https://example.com/spoolman/api/v1/spool"),
        ("https://example.com/tools/3d/spoolman", "https://example.com/tools/3d/spoolman/api/v1/spool"),
        ("https://example.com:8443/spoolman", "https://example.com:8443/spoolman/api/v1/spool"),
        ("http://[fd00::1]:7912", "http://[fd00::1]:7912/api/v1/spool"),
        ("http://[fd00::1]:7912/spoolman", "http://[fd00::1]:7912/spoolman/api/v1/spool"),
        ("https://[2001:db8::10]/spoolman", "https://[2001:db8::10]/spoolman/api/v1/spool"),
    ])
    func buildsEndpointFromBase(base: String, expected: String) throws {
        #expect(try Self.endpoint(base) == expected)
    }

    // MARK: - Normalisation

    @Test(arguments: [
        "https://example.com/spoolman/",
        "https://example.com/spoolman//",
        "  https://example.com/spoolman  ",
        "\nhttps://example.com/spoolman/\n",
        "HTTPS://example.com/spoolman",
    ])
    func normalisesToSameBase(raw: String) throws {
        let base = try SpoolmanBaseURL(raw)
        #expect(base.url.absoluteString == "https://example.com/spoolman")
        #expect(base.endpoint("/api/v1/vendor")?.absoluteString == "https://example.com/spoolman/api/v1/vendor")
    }

    @Test func rootWithTrailingSlashHasNoDoubleSlash() throws {
        #expect(try Self.endpoint("http://host:7912/") == "http://host:7912/api/v1/spool")
        #expect(try Self.endpoint("http://host:7912///") == "http://host:7912/api/v1/spool")
    }

    @Test func endpointWithoutLeadingSlashStillJoinsOnce() throws {
        #expect(try Self.endpoint("https://example.com/spoolman", "api/v1/spool") == "https://example.com/spoolman/api/v1/spool")
    }

    @Test func pathCaseIsPreserved() throws {
        #expect(try Self.endpoint("https://example.com/SpoolMan") == "https://example.com/SpoolMan/api/v1/spool")
    }

    @Test func preEncodedEndpointIsNotEncodedTwice() throws {
        // renameLocation percent-encodes the location name before building the endpoint.
        #expect(try Self.endpoint("https://example.com/spoolman", "/api/v1/location/Shelf%20A%2F1")
            == "https://example.com/spoolman/api/v1/location/Shelf%20A%2F1")
    }

    @Test func percentEncodedBasePathSurvives() throws {
        #expect(try Self.endpoint("https://example.com/my%20tools/spoolman") == "https://example.com/my%20tools/spoolman/api/v1/spool")
    }

    @Test func addressWithSpaceOrNonASCIIHostIsPercentEncodedNotRejected() throws {
        #expect(try Self.endpoint("https://example.com/my tools/spoolman") == "https://example.com/my%20tools/spoolman/api/v1/spool")
        #expect(try Self.endpoint("https://exämple.com/spoolman") == "https://xn--exmple-cua.com/spoolman/api/v1/spool")
    }

    @Test(arguments: ["/api/v1/spool?allow_archived=true", "/api/v1/spool#x", "/api/v1/spool?"])
    func endpointWithQueryOrFragmentIsRefused(path: String) throws {
        #expect(try SpoolmanBaseURL("https://example.com/spoolman").endpoint(path) == nil)
    }

    // MARK: - Rejections

    @Test(arguments: [
        ("", SpoolmanBaseURL.ParseError.empty),
        ("   \n", .empty),
        ("example.com/spoolman", .unsupportedScheme(nil)),
        ("ftp://example.com", .unsupportedScheme("ftp")),
        ("http://", .missingHost),
        ("https://example.com/spoolman?x=1", .hasQuery),
        ("https://example.com/spoolman/?", .hasQuery),
        ("https://example.com/spoolman#top", .hasFragment),
        ("https://user:secret@example.com/spoolman", .hasUserInfo),
        ("https://user@example.com/spoolman", .hasUserInfo),
    ])
    func rejectsBadAddress(raw: String, expected: SpoolmanBaseURL.ParseError) {
        #expect(throws: expected) { try SpoolmanBaseURL(raw) }
    }

    @Test func everyRejectionHasAUserFacingMessage() {
        let errors: [SpoolmanBaseURL.ParseError] = [.empty, .unsupportedScheme(nil), .missingHost, .hasQuery, .hasFragment, .hasUserInfo, .invalid]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    // MARK: - Origin

    @Test func sameOriginIgnoresPathAndDefaultPort() throws {
        let base = try SpoolmanBaseURL("https://Example.com/spoolman")
        #expect(base.isSameOrigin(as: URL(string: "https://example.com/other/path")!))
        #expect(base.isSameOrigin(as: URL(string: "https://example.com:443/x")!))
    }

    @Test func differentHostPortOrSchemeIsForeign() throws {
        let base = try SpoolmanBaseURL("https://example.com/spoolman")
        #expect(!base.isSameOrigin(as: URL(string: "https://donkie.github.io/SpoolmanDB/filaments.json")!))
        #expect(!base.isSameOrigin(as: URL(string: "https://example.com:8443/spoolman")!))
        #expect(!base.isSameOrigin(as: URL(string: "http://example.com/spoolman")!))
    }

    @Test func sameExplicitPortWithDifferentSchemeIsForeign() throws {
        let base = try SpoolmanBaseURL("https://example.com:8443/spoolman")
        #expect(!base.isSameOrigin(as: URL(string: "http://example.com:8443/spoolman")!))
    }

    @Test func hostComparisonIgnoresCaseOnTheCandidate() throws {
        let base = try SpoolmanBaseURL("https://example.com/spoolman")
        #expect(base.isSameOrigin(as: URL(string: "https://EXAMPLE.com/x")!))
    }

    @Test func sameOriginWorksForIPv6() throws {
        let base = try SpoolmanBaseURL("http://[fd00::1]:7912/spoolman")
        #expect(base.isSameOrigin(as: URL(string: "http://[fd00::1]:7912/api")!))
        #expect(!base.isSameOrigin(as: URL(string: "http://[fd00::2]:7912/api")!))
    }
}
