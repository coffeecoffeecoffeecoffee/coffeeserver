import Foundation
import Testing
import VaporTesting

@testable import App

/// Logs in with HTTP Basic auth and returns the session JWT.
func login(app: Application, email: String, password: String) async throws -> String {
    let encodedLogin = Data("\(email):\(password)".utf8).base64EncodedString()
    var token: String?
    try await app.testing().test(
        .POST,
        "/api/v2/users/login",
        headers: ["Authorization": "Basic \(encodedLogin)"]
    ) { res async in
        #expect(res.status == .ok)
        let json = try? JSONDecoder().decode([String: String].self, from: Data(buffer: res.body))
        token = json?["jwt-token"]
    }
    return try #require(token)
}

/// Logs in as the admin created by the `AddSuperUser` migration.
func loginAsAdmin(app: Application) async throws -> String {
    try await login(
        app: app,
        email: try #require(Environment.get("SERVER_ADMIN_EMAIL")),
        password: try #require(Environment.get("SERVER_ADMIN_PASSWORD"))
    )
}
