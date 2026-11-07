import CoffeeKit
import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Web Account Tests")
struct WebAccountTests {

    let name = "Grace Hopper"
    let email = "grace@example.com"
    let password = "Nanoseconds 11.8"

    // MARK: Header

    @Test("Signed-out pages link to Sign In and set no cookie")
    func signedOutHeader() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "/") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains(#"<a href="/signin" class="white-button">Sign In</a>"#))
                #expect(res.headers.first(name: .setCookie) == nil, "Browsing doesn't start a session")
                #expect(res.headers.first(name: .cacheControl) == "private, no-cache")
            }
            #expect(try await SessionRecord.query(on: app.db).count() == 0, "No session is stored")
        }
    }

    // MARK: Sign-up

    @Test("Sign-up lands on the account page and signs the user in everywhere")
    func signUpThenAccount() async throws {
        try await withApp(configure: configure) { app in
            var cookie: String?
            try await app.testing().test(
                .POST, "/signup",
                headers: formHeaders(),
                body: form(["name": name, "email": "Grace@Example.com", "password": password, "confirmPassword": password])
            ) { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/account")
                let setCookie = res.headers.first(name: .setCookie) ?? ""
                #expect(setCookie.hasPrefix("\(WebSession.cookieName)="))
                #expect(setCookie.contains("HttpOnly"))
                #expect(setCookie.contains("SameSite=Lax"))
                cookie = sessionCookie(res)
            }
            let session = try #require(cookie)

            try await app.testing().test(.GET, "/account", headers: ["Cookie": session]) { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains(name))
                #expect(res.body.string.contains(email), "Email is shown, stored lowercased")
            }
            try await app.testing().test(.GET, "/", headers: ["Cookie": session]) { res async in
                #expect(res.body.string.contains(#"<a href="/account" class="white-button">\#(name)</a>"#))
                #expect(!res.body.string.contains(">Sign In<"))
            }
        }
    }

    @Test("Sign-up errors re-render the page without a session")
    func signUpErrors() async throws {
        try await withApp(configure: configure) { app in
            _ = try await User.register(
                UserCreate(name: name, email: email, password: password, confirmPassword: password), on: app.db
            )
            let cases: [([String: String], String)] = [
                (["name": "New", "email": "new@example.com", "password": "short", "confirmPassword": "short"],
                 "Please check your details"),
                (["name": "New", "email": "new@example.com", "password": password, "confirmPassword": "Different 123"],
                 "The passwords don&#39;t match."),
                (["name": "New", "email": email, "password": password, "confirmPassword": password],
                 "An account with that email already exists."),
            ]
            for (fields, message) in cases {
                try await app.testing().test(.POST, "/signup", headers: formHeaders(), body: form(fields)) { res async in
                    #expect(res.status == .badRequest)
                    let body = res.body.string.replacingOccurrences(of: "'", with: "&#39;")
                    #expect(body.contains(message), "Shows: \(message)")
                    #expect(res.headers.first(name: .setCookie) == nil)
                }
            }
        }
    }

    // MARK: Sign-in

    @Test("Sign-in with a good password redirects with a session; bad ones get the same error")
    func signIn() async throws {
        try await withApp(configure: configure) { app in
            try await makeUser(app: app)

            try await app.testing().test(
                .POST, "/signin", headers: formHeaders(), body: form(["email": email, "password": password])
            ) { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/account")
                #expect(sessionCookie(res) != nil)
            }

            for (badEmail, badPassword) in [(email, "Wrong password 1"), ("nobody@example.com", password)] {
                try await app.testing().test(
                    .POST, "/signin", headers: formHeaders(), body: form(["email": badEmail, "password": badPassword])
                ) { res async in
                    #expect(res.status == .unauthorized)
                    #expect(res.body.string.contains("Email or password is incorrect."))
                    #expect(res.body.string.contains(#"value="\#(badEmail)""#), "Email is kept")
                    #expect(!res.body.string.contains(badPassword), "Password is never filled back in")
                    #expect(res.headers.first(name: .setCookie) == nil)
                }
            }
        }
    }

    @Test("Signing in replaces the session ID the browser arrived with")
    func signInRotatesSession() async throws {
        try await withApp(configure: configure) { app in
            try await makeUser(app: app)
            let first = try await signIn(app: app)
            var second: String?

            try await app.testing().test(
                .POST, "/signin",
                headers: formHeaders(cookie: first),
                body: form(["email": email, "password": password])
            ) { res async in
                #expect(res.status == .seeOther)
                second = sessionCookie(res)
            }

            let rotated = try #require(second)
            #expect(rotated != first, "A new session ID is issued")
            try await expectSignedOut(app: app, cookie: first)
            try await app.testing().test(.GET, "/account", headers: ["Cookie": rotated]) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("Signed-in visitors skip the sign-in page")
    func signInPageRedirectsWhenSignedIn() async throws {
        try await withApp(configure: configure) { app in
            try await makeUser(app: app)
            let session = try await signIn(app: app)
            try await app.testing().test(.GET, "/signin", headers: ["Cookie": session]) { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/account")
            }
            try await app.testing().test(.GET, "/signin") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains(#"autocomplete="username webauthn""#), "Ready for passkey autofill")
            }
        }
    }

    // MARK: Account and sign-out

    @Test("The account page requires a session")
    func accountRequiresSession() async throws {
        try await withApp(configure: configure) { app in
            try await expectSignedOut(app: app, cookie: nil)
            try await expectSignedOut(app: app, cookie: "\(WebSession.cookieName)=not-a-real-session")
            #expect(try await SessionRecord.query(on: app.db).count() == 0,
                    "A made-up cookie doesn't create a stored session")
        }
    }

    @Test("Signing out ends the session")
    func signOut() async throws {
        try await withApp(configure: configure) { app in
            try await makeUser(app: app)
            let session = try await signIn(app: app)

            try await app.testing().test(.POST, "/signout", headers: formHeaders(cookie: session)) { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/")
                #expect(res.headers.first(name: .setCookie)?.contains("Max-Age=0") == true
                        || res.headers.first(name: .setCookie)?.contains("Expires=Thu, 01 Jan 1970") == true,
                        "Cookie is expired")
            }
            try await expectSignedOut(app: app, cookie: session)
        }
    }

    // MARK: Security

    @Test("Cross-site form posts are rejected")
    func crossSitePostRejected() async throws {
        try await withApp(configure: configure) { app in
            try await makeUser(app: app)
            let fields = ["email": email, "password": password]

            var headers = formHeaders()
            headers.replaceOrAdd(name: .host, value: "coffee.example.com")
            headers.replaceOrAdd(name: .origin, value: "https://evil.example")
            try await app.testing().test(.POST, "/signin", headers: headers, body: form(fields)) { res async in
                #expect(res.status == .forbidden)
                #expect(res.headers.first(name: .setCookie) == nil)
            }

            headers.replaceOrAdd(name: .origin, value: "https://coffee.example.com")
            try await app.testing().test(.POST, "/signin", headers: headers, body: form(fields)) { res async in
                #expect(res.status == .seeOther, "Same-site posts still work")
            }
        }
    }

    @Test("User-supplied text is escaped in the header and in form fields")
    func userTextIsEscaped() async throws {
        try await withApp(configure: configure) { app in
            let scriptName = "<script>alert(1)</script>"
            _ = try await User.register(
                UserCreate(name: scriptName, email: email, password: password, confirmPassword: password), on: app.db
            )
            let session = try await signIn(app: app)
            try await app.testing().test(.GET, "/", headers: ["Cookie": session]) { res async in
                #expect(!res.body.string.contains(scriptName))
                #expect(res.body.string.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
            }

            let attack = #""><script>alert(2)</script>"#
            try await app.testing().test(
                .POST, "/signin", headers: formHeaders(), body: form(["email": attack, "password": "x"])
            ) { res async in
                #expect(!res.body.string.contains(attack), "Can't break out of the value attribute")
                #expect(res.body.string.contains("&quot;&gt;&lt;script&gt;alert(2)&lt;/script&gt;"))
            }
        }
    }

    @Test("Groups cannot take a slug used by a site page")
    func reservedSlugsRejected() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            for slug in ["account", "SignIn"] {
                try await app.testing().test(
                    .POST, "/api/v2/groups",
                    headers: ["Content-Type": "application/json", "Authorization": "Bearer \(adminJWT)"],
                    body: ByteBuffer(string: #"{"name": "Sneaky", "short": "\#(slug)"}"#)
                ) { res async in
                    #expect(res.status == .badRequest, "\(slug) is reserved")
                }
            }
            #expect(try await InterestGroup.query(on: app.db).filter(\.$name == "Sneaky").count() == 0)
        }
    }

    // MARK: - Helpers

    private func makeUser(app: Application) async throws {
        _ = try await User.register(
            UserCreate(name: name, email: email, password: password, confirmPassword: password), on: app.db
        )
    }

    /// Signs in through the web form and returns the `Cookie` header value for the new session.
    private func signIn(app: Application) async throws -> String {
        var cookie: String?
        try await app.testing().test(
            .POST, "/signin", headers: formHeaders(), body: form(["email": email, "password": password])
        ) { res async in
            #expect(res.status == .seeOther)
            cookie = sessionCookie(res)
        }
        return try #require(cookie)
    }

    private func expectSignedOut(
        app: Application, cookie: String?, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let headers: HTTPHeaders = cookie.map { ["Cookie": $0] } ?? [:]
        try await app.testing().test(.GET, "/account", headers: headers) { res async in
            #expect(res.status == .seeOther, sourceLocation: sourceLocation)
            #expect(res.headers.first(name: .location) == "/signin", sourceLocation: sourceLocation)
        }
    }

    /// `name=value` for the session cookie a response sets, ready to send back as a `Cookie` header.
    private func sessionCookie(_ res: TestingHTTPResponse) -> String? {
        guard let value = res.headers.setCookie?[WebSession.cookieName]?.string, !value.isEmpty else {
            return nil
        }
        return "\(WebSession.cookieName)=\(value)"
    }

    private func formHeaders(cookie: String? = nil) -> HTTPHeaders {
        var headers: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        if let cookie {
            headers.add(name: .cookie, value: cookie)
        }
        return headers
    }

    private func form(_ fields: [String: String]) -> ByteBuffer {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return ByteBuffer(string: body)
    }
}
