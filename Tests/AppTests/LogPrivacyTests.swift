import CoffeeKit
import Foundation
import Logging
import Testing
import VaporTesting

@testable import App

@Suite("Log Privacy Tests")
struct LogPrivacyTests {

    let email = "private.person@example.com"
    let password = "Secret password 123"
    let otherEmail = "someone.else@example.com"

    @Test("Failed logins don't log the email, password, or Authorization header")
    func failedLoginsAreNotLogged() async throws {
        let logs = LogCapture()
        try await withCapturingApp(logs) { app in
            try await createUser(app: app, email: email)

            for (loginEmail, loginPassword) in [(email, "wrong password"), ("nobody@example.com", password)] {
                let credentials = Data("\(loginEmail):\(loginPassword)".utf8).base64EncodedString()
                try await app.testing().test(
                    .POST, "/api/v2/users/login",
                    headers: ["Authorization": "Basic \(credentials)"]
                ) { res async in
                    #expect(res.status != .ok)
                }
                logs.expectNotLogged(loginEmail, loginPassword, credentials)
            }
            logs.expectNotLogged(email, password)
        }
    }

    @Test("Duplicate emails on sign-up and profile update aren't logged")
    func duplicateEmailsAreNotLogged() async throws {
        let logs = LogCapture()
        try await withCapturingApp(logs) { app in
            try await createUser(app: app, email: email)
            try await createUser(app: app, email: otherEmail)

            // Sign up again with an email that's taken
            try await app.testing().test(
                .POST, "/api/v2/users",
                headers: ["Content-Type": "application/json"],
                body: try userBody(email: email)
            ) { res async in
                #expect(res.status == .badRequest)
            }

            // Change a profile's email to one that's taken
            let jwt = try await login(app: app, email: otherEmail, password: password)
            try await app.testing().test(
                .PUT, "/api/v2/users/me",
                headers: ["Content-Type": "application/json", "Authorization": "Bearer \(jwt)"],
                body: try userBody(email: email)
            ) { res async in
                #expect(res.status == .badRequest)
            }

            logs.expectNotLogged(email, otherEmail, password, jwt)
        }
    }

    @Test("Unauthorized requests don't log the session token or request body")
    func unauthorizedRequestsAreNotLogged() async throws {
        let logs = LogCapture()
        try await withCapturingApp(logs) { app in
            try await createUser(app: app, email: email)
            let jwt = try await login(app: app, email: email, password: password)

            // A non-admin trying an admin-only action
            try await app.testing().test(
                .POST, "/api/v2/venues",
                headers: ["Content-Type": "application/json", "Authorization": "Bearer \(jwt)"],
                body: ByteBuffer(string: #"{"name": "Contact \#(email)"}"#)
            ) { res async in
                #expect(res.status == .unauthorized)
            }

            #expect(logs.messages.contains { $0.contains("Unauthorized venue creation attempt") },
                    "The attempt itself is still logged")
            logs.expectNotLogged(email, jwt)
        }
    }

    // MARK: - Helpers

    /// Runs `test` against an app whose logs, at `info` and above, are recorded in `logs`.
    private func withCapturingApp(
        _ logs: LogCapture,
        _ test: (Application) async throws -> Void
    ) async throws {
        try await withApp(configure: { app in
            app.logger = Logger(label: "log-privacy-tests") { _ in LogCapture.Handler(capture: logs) }
            try configure(app)
        }, test)
    }

    private func userBody(email: String) throws -> ByteBuffer {
        let user = UserCreate(name: "Private Person", email: email, password: password, confirmPassword: password)
        return ByteBuffer(data: try JSONEncoder().encode(user))
    }

    private func createUser(app: Application, email: String) async throws {
        try await app.testing().test(
            .POST, "/api/v2/users",
            headers: ["Content-Type": "application/json"],
            body: try userBody(email: email)
        ) { res async in
            #expect(res.status == .created)
        }
    }
}

/// Collects log lines, with their metadata, so tests can check what was written.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    var messages: [String] {
        lock.withLock { lines }
    }

    func record(_ line: String) {
        lock.withLock { lines.append(line) }
    }

    /// Records an issue for each value that appears in any log line.
    func expectNotLogged(_ values: String..., sourceLocation: SourceLocation = #_sourceLocation) {
        let logged = messages
        #expect(!logged.isEmpty, "Logs were captured", sourceLocation: sourceLocation)
        for value in values {
            let leaks = logged.filter { $0.localizedCaseInsensitiveContains(value) }
            #expect(leaks.isEmpty, "Logged \"\(value)\":\n\(leaks.joined(separator: "\n"))", sourceLocation: sourceLocation)
        }
    }

    struct Handler: LogHandler {
        let capture: LogCapture
        var metadata: Logger.Metadata = [:]
        /// Production's level (`LOG_LEVEL` in docker-compose.yml). At `.debug`, Fluent logs query values, emails included.
        var logLevel: Logger.Level = .info

        subscript(metadataKey key: String) -> Logger.Metadata.Value? {
            get { metadata[key] }
            set { metadata[key] = newValue }
        }

        func log(
            level: Logger.Level,
            message: Logger.Message,
            metadata explicitMetadata: Logger.Metadata?,
            source: String,
            file: String,
            function: String,
            line: UInt
        ) {
            let merged = metadata.merging(explicitMetadata ?? [:]) { _, new in new }
            capture.record("\(level) \(message) \(merged)")
        }
    }
}
