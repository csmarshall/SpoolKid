//
//  SpoolmanResponseCheckTests.swift
//  SpoolKidTests
//
//  Tests for recognising a reverse proxy's login page, both the decision on its
//  own and through each of SpoolmanService's four request paths.
//

import Foundation
import Testing
@testable import SpoolKid

struct SpoolmanResponseCheckTests {
    @Test(arguments: [200, 204, 401, 403])
    func htmlWhereJSONWasExpectedIsALoginPage(status: Int) {
        let error = SpoolmanResponseCheck.loginPageError(statusCode: status, mimeType: "text/html")
        #expect(error?.code == status)
        #expect(error?.localizedDescription == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test(arguments: ["text/html; charset=utf-8", "TEXT/HTML", " text/html ", "application/xhtml+xml"])
    func htmlIsRecognisedWithParametersAndCase(mime: String) {
        #expect(SpoolmanResponseCheck.isHTML(mimeType: mime))
    }

    @Test(arguments: ["application/json", "text/plain", "image/png", ""])
    func otherTypesAreNotHTML(mime: String) {
        #expect(!SpoolmanResponseCheck.isHTML(mimeType: mime))
        #expect(SpoolmanResponseCheck.loginPageError(statusCode: 200, mimeType: mime) == nil)
    }

    @Test func missingContentTypeIsNotALoginPage() {
        #expect(SpoolmanResponseCheck.loginPageError(statusCode: 200, mimeType: nil) == nil)
    }

    @Test(arguments: [404, 500, 502, 503])
    func proxyErrorPagesStayOrdinaryServerErrors(status: Int) {
        #expect(SpoolmanResponseCheck.loginPageError(statusCode: status, mimeType: "text/html") == nil)
    }

    @Test(arguments: [200, 401])
    func jsonResponsesAreNeverALoginPage(status: Int) {
        #expect(SpoolmanResponseCheck.loginPageError(statusCode: status, mimeType: "application/json") == nil)
    }
}

/// The same check as seen through SpoolmanService: each request path must report it.
extension StubbedNetwork {
@MainActor
@Suite
struct SpoolmanLoginPageWiringTests {
    private let base = "https://spoolkid-stub.invalid/spoolman"

    init() {
        UserDefaults.standard.removeObject(forKey: AppConfig.trustAllCertsKey)
        URLProtocol.registerClass(RecordingURLProtocol.self)
        RecordingURLProtocol.reset()
        RecordingURLProtocol.contentType = "text/html; charset=utf-8"
        RecordingURLProtocol.body = "<html><body>Sign in to continue</body></html>"
    }

    @Test func testConnectionReportsLoginPage() async {
        let service = SpoolmanService()
        let ok = await service.testConnection(baseUrl: base)
        #expect(!ok)
        #expect(service.errorMessage == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test func listFetchReportsLoginPage() async {
        let service = SpoolmanService()
        await service.fetchSpools(baseUrl: base)
        #expect(service.errorMessage == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test func deleteReportsLoginPage() async {
        let service = SpoolmanService()
        await service.deleteVendor(id: 1, baseUrl: base)
        #expect(service.errorMessage == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test func nonDecodingRequestReportsLoginPage() async {
        let service = SpoolmanService()
        let ok = await service.renameLocation(currentName: "A", newName: "B", baseUrl: base)
        #expect(!ok)
        #expect(service.errorMessage == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test func unauthorizedHtmlAlsoReportsLoginPage() async {
        RecordingURLProtocol.status = 401
        let service = SpoolmanService()
        #expect(!(await service.testConnection(baseUrl: base)))
        #expect(service.errorMessage == SpoolmanResponseCheck.loginPageMessage)
    }

    @Test func realJSONErrorMessageIsStillShown() async {
        RecordingURLProtocol.status = 401
        RecordingURLProtocol.contentType = "application/json"
        RecordingURLProtocol.body = "{\"message\":\"Bad token\"}"
        let service = SpoolmanService()
        #expect(!(await service.testConnection(baseUrl: base)))
        #expect(service.errorMessage == "Bad token")
    }
}
}
