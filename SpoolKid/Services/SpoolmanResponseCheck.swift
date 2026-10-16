//
//  SpoolmanResponseCheck.swift
//  SpoolKid
//
//  Purpose: Recognises a reverse proxy's login page. A proxy that wants a
//  session answers an API call with an HTML page (after redirects, usually
//  200; or 401/403), which otherwise surfaces as an opaque JSON decoding error.
//

import Foundation

nonisolated enum SpoolmanResponseCheck {
    static let loginPageMessage = "The server returned a web page instead of Spoolman data. A reverse proxy in front of Spoolman is probably asking you to sign in. Check the authentication settings, or allow API access for SpoolKid in the proxy."

    /// An error when the response is an HTML page where an API answer was expected
    /// and the status is one a login page uses (success, 401 or 403). Other statuses
    /// with an HTML body, such as a proxy's 502 page, are ordinary server errors.
    static func loginPageError(statusCode: Int, mimeType: String?) -> NSError? {
        guard isHTML(mimeType: mimeType), (200...299).contains(statusCode) || statusCode == 401 || statusCode == 403 else {
            return nil
        }
        return NSError(domain: "SpoolmanError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: loginPageMessage])
    }

    static func isHTML(mimeType: String?) -> Bool {
        guard let essence = mimeType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return false
        }
        return essence == "text/html" || essence == "application/xhtml+xml"
    }
}
