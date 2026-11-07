import Fluent
import Vapor

/// Cookie-backed sessions for the web pages. The JSON API keeps using Bearer JWTs.
///
/// Every way of signing in (password today, passkeys next) ends in ``signIn(_:on:)``,
/// so session handling stays independent of how the user proved who they are.
enum WebSession {
    static let cookieName = "coffee-session"
    static let lifetime: TimeInterval = 60 * 60 * 24 * 30

    /// Stores sessions in the database so they survive restarts, with a strictly necessary,
    /// script-inaccessible cookie (`Secure` in production).
    static func configure(_ app: Application) {
        app.sessions.use(.fluent)
        let isSecure = app.environment == .production
        app.sessions.configuration = .init(cookieName: cookieName) { sessionID in
            HTTPCookies.Value(
                string: sessionID.string,
                expires: Date(timeIntervalSinceNow: lifetime),
                path: "/",
                isSecure: isSecure,
                isHTTPOnly: true,
                sameSite: .lax
            )
        }
    }

    /// Middleware for web routes: loads the session, restores the signed-in ``User``,
    /// and rejects cross-site form posts.
    static func middleware(for app: Application) -> [any Middleware] {
        [app.sessions.middleware, WebSessionUserMiddleware(), WebOriginCheckMiddleware()]
    }

    /// Signs `user` in under a new session ID, discarding any session the request arrived with,
    /// so an ID planted before sign-in is never upgraded to a signed-in session.
    static func signIn(_ user: User, on req: Request) async throws {
        if let oldID = req.session.id {
            try await req.application.sessions.driver.deleteSession(oldID, for: req).get()
            req.session.id = nil
            req.session.data = SessionData()
        }
        req.session.authenticate(user)
        req.auth.login(user)
    }

    /// Ends the session; the response expires the cookie and deletes the stored session.
    static func signOut(on req: Request) {
        req.auth.logout(User.self)
        req.session.unauthenticate(User.self)
        req.session.destroy()
    }
}

/// Restores the signed-in ``User`` from an existing session.
///
/// Used instead of Fluent's `User.sessionAuthenticator()`, which reads `req.session` on every request.
/// Reading it creates a session, so every anonymous visitor would get a cookie and a stored session.
struct WebSessionUserMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if request.hasSession, let userID = request.session.authenticated(User.self) {
            if let user = try await User.find(userID, on: request.db) {
                request.auth.login(user)
            } else {
                // The account was deleted; drop its session.
                request.session.destroy()
            }
        }
        let response = try await next.respond(to: request)
        // A cookie for an unknown or expired session makes Vapor start a fresh one. If nothing was
        // stored in it, drop it rather than saving an empty session and handing out a new cookie.
        if request.hasSession, request.session.data.snapshot.isEmpty {
            request.session.destroy()
        }
        return response
    }
}

/// Rejects form posts whose `Origin` names another site. `SameSite=Lax` already keeps the session
/// cookie off cross-site posts; this also stops another site signing a visitor into an account.
struct WebOriginCheckMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .POST,
              let origin = request.headers.first(name: .origin) else {
            return try await next.respond(to: request)
        }
        // Origin and Host both omit default ports, so "host[:port]" compares directly.
        guard let host = request.headers.first(name: .host)?.lowercased(),
              let originURL = URL(string: origin),
              let originHost = originURL.host?.lowercased(),
              originHost + (originURL.port.map { ":\($0)" } ?? "") == host
        else {
            request.logger.warning("Rejected cross-site form post")
            throw Abort(.forbidden, reason: "Cross-site form posts are not allowed")
        }
        return try await next.respond(to: request)
    }
}
