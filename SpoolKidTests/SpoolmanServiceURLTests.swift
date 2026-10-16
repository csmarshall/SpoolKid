//
//  SpoolmanServiceURLTests.swift
//  SpoolKidTests
//
//  Tests that SpoolmanService builds request URLs from the typed server
//  address, including sub-path deployments behind a reverse proxy.
//

import Foundation
import Testing
@testable import SpoolKid

@MainActor
struct SpoolmanServiceURLTests {
    @Test(arguments: [
        ("http://192.168.1.10:7912", "http://192.168.1.10:7912/api/v1/spool"),
        ("http://192.168.1.10:7912/spoolman", "http://192.168.1.10:7912/spoolman/api/v1/spool"),
        ("https://example.com/spoolman/", "https://example.com/spoolman/api/v1/spool"),
        ("  https://example.com/spoolman \n", "https://example.com/spoolman/api/v1/spool"),
        ("http://[fd00::1]:7912/spoolman/", "http://[fd00::1]:7912/spoolman/api/v1/spool"),
    ])
    func requestURLJoinsBaseAndEndpoint(base: String, expected: String) throws {
        #expect(try SpoolmanService.requestURL(baseUrl: base, endpoint: "/api/v1/spool").absoluteString == expected)
    }

    @Test func requestURLKeepsPreEncodedLocationName() throws {
        let url = try SpoolmanService.requestURL(baseUrl: "https://example.com/spoolman", endpoint: "/api/v1/location/Shelf%20A")
        #expect(url.absoluteString == "https://example.com/spoolman/api/v1/location/Shelf%20A")
    }

    @Test(arguments: ["", "example.com/spoolman", "https://example.com/spoolman?x=1", "ftp://example.com"])
    func requestURLRejectsBadAddress(base: String) {
        #expect(throws: SpoolmanBaseURL.ParseError.self) {
            try SpoolmanService.requestURL(baseUrl: base, endpoint: "/api/v1/spool")
        }
    }
}

/// Records every request URL it sees and answers 200 with an empty JSON array,
/// so a test can check which URL each SpoolmanService call really hits.
final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requested: [URL] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { requested = [] } }
    static func snapshot() -> [URL] { lock.withLock { requested } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "spoolkid-stub.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.lock.withLock { Self.requested.append(url) } }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Drives each of SpoolmanService's four request paths and checks the URL on the wire.
@MainActor
@Suite(.serialized)
struct SpoolmanServiceWiringTests {
    private let base = "https://spoolkid-stub.invalid/spoolman/"

    init() {
        URLProtocol.registerClass(RecordingURLProtocol.self)
        RecordingURLProtocol.reset()
    }

    @Test func decodingRequestUsesSubPathWithoutDoubleSlash() async {
        let ok = await SpoolmanService().testConnection(baseUrl: base)
        #expect(ok)
        #expect(RecordingURLProtocol.snapshot().map(\.absoluteString) == ["https://spoolkid-stub.invalid/spoolman/api/v1/vendor"])
    }

    @Test func listFetchUsesSubPathWithoutDoubleSlash() async {
        await SpoolmanService().fetchSpools(baseUrl: base)
        #expect(RecordingURLProtocol.snapshot().map(\.absoluteString) == ["https://spoolkid-stub.invalid/spoolman/api/v1/spool"])
    }

    @Test func deleteRequestUsesSubPathWithoutDoubleSlash() async {
        await SpoolmanService().deleteVendor(id: 7, baseUrl: base)
        #expect(RecordingURLProtocol.snapshot().map(\.absoluteString).first == "https://spoolkid-stub.invalid/spoolman/api/v1/vendor/7")
    }

    @Test func nonDecodingRequestUsesSubPathAndKeepsEncodedName() async {
        _ = await SpoolmanService().renameLocation(currentName: "Shelf A/1", newName: "Shelf B", baseUrl: base)
        #expect(RecordingURLProtocol.snapshot().map(\.absoluteString).first == "https://spoolkid-stub.invalid/spoolman/api/v1/location/Shelf%20A%2F1")
    }

    @Test func badAddressSurfacesAnErrorInsteadOfRequesting() async {
        let service = SpoolmanService()
        await service.fetchSpools(baseUrl: "spoolkid-stub.invalid/spoolman")
        #expect(service.errorMessage?.contains("http://") == true)
        #expect(RecordingURLProtocol.snapshot().isEmpty)
    }
}
