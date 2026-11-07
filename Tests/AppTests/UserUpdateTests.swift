import CoffeeKit
import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("User Update Tests")
struct UserUpdateTests {

    let email = "ada@example.com"
    let password = "Original password 1"
    let newPassword = "Brand new password 2"

    @Test("User updates their name and keeps the same email")
    func selfUpdateKeepingEmail() async throws {
        try await withApp(configure: configure) { app in
            let user = try await makeUser(app: app, email: email)
            let jwt = try await login(app: app, email: email, password: password)

            let updated = try await update(app: app, path: "me", jwt: jwt, name: "Ada Lovelace", email: email)

            #expect(updated?.name == "Ada Lovelace")
            #expect(updated?.email == email)
            #expect(try await User.find(user.requireID(), on: app.db)?.name == "Ada Lovelace")
        }
    }

    @Test("User keeps the same email typed in different case")
    func selfUpdateKeepingEmailDifferentCase() async throws {
        try await withApp(configure: configure) { app in
            let user = try await makeUser(app: app, email: email)
            let jwt = try await login(app: app, email: email, password: password)

            let updated = try await update(app: app, path: "me", jwt: jwt, name: "Ada", email: "Ada@Example.com")

            #expect(updated?.email == email, "Email is stored lowercased, as at sign-up")
            #expect(try await User.find(user.requireID(), on: app.db)?.email == email)
            _ = try await login(app: app, email: email, password: newPassword)
        }
    }

    @Test("User changes to a new email and password, then logs in with them")
    func selfUpdateNewEmail() async throws {
        try await withApp(configure: configure) { app in
            _ = try await makeUser(app: app, email: email)
            let jwt = try await login(app: app, email: email, password: password)

            let updated = try await update(app: app, path: "me", jwt: jwt, name: "Ada", email: "Countess@Example.com")

            #expect(updated?.email == "countess@example.com")
            _ = try await login(app: app, email: "countess@example.com", password: newPassword)
        }
    }

    @Test("User cannot take another user's email, in any case")
    func selfUpdateTakenEmailRejected() async throws {
        try await withApp(configure: configure) { app in
            _ = try await makeUser(app: app, email: email)
            let other = try await makeUser(app: app, email: "other@example.com")
            let jwt = try await login(app: app, email: "other@example.com", password: password)

            for takenEmail in [email, "ADA@example.com"] {
                let updated = try await update(
                    app: app, path: "me", jwt: jwt, name: "Other", email: takenEmail, expecting: .badRequest
                )
                #expect(updated == nil)
            }
            #expect(try await User.find(other.requireID(), on: app.db)?.email == "other@example.com")
        }
    }

    @Test("Admin updates another user who keeps the same email")
    func adminUpdateKeepingEmail() async throws {
        try await withApp(configure: configure) { app in
            let user = try await makeUser(app: app, email: email)
            let adminJWT = try await loginAsAdmin(app: app)

            let updated = try await update(
                app: app, path: try user.requireID().uuidString, jwt: adminJWT, name: "Ada (edited)", email: email
            )

            #expect(updated?.name == "Ada (edited)")
            #expect(updated?.email == email)
        }
    }

    @Test("Sign-up with an existing email in different case is rejected")
    func signUpTakenEmailDifferentCase() async throws {
        try await withApp(configure: configure) { app in
            _ = try await makeUser(app: app, email: email)
            let body = UserCreate(name: "Imposter", email: "ADA@Example.com", password: password, confirmPassword: password)

            try await app.testing().test(
                .POST, "/api/v2/users",
                headers: ["Content-Type": "application/json"],
                body: ByteBuffer(data: try JSONEncoder().encode(body))
            ) { res async in
                #expect(res.status == .badRequest, "Rejected cleanly, not a 500 from the database")
            }
            #expect(try await User.query(on: app.db).filter(\.$name == "Imposter").count() == 0)
        }
    }

    // MARK: - Helpers

    private func makeUser(app: Application, email: String) async throws -> User {
        let user = try User(name: "Ada", email: email, passwordHash: Bcrypt.hash(password))
        try await user.save(on: app.db)
        return user
    }

    /// Sends `PUT /api/v2/users/<path>` and returns the decoded user when the response is `expected`.
    private func update(
        app: Application,
        path: String,
        jwt: String,
        name: String,
        email: String,
        expecting expected: HTTPStatus = .ok,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> UserPrivate? {
        let body = UserCreate(name: name, email: email, password: newPassword, confirmPassword: newPassword)
        var result: UserPrivate?
        try await app.testing().test(
            .PUT, "/api/v2/users/\(path)",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer \(jwt)"],
            body: ByteBuffer(data: try JSONEncoder().encode(body))
        ) { res async in
            #expect(res.status == expected, "\(res.body.string)", sourceLocation: sourceLocation)
            if res.status == .ok {
                result = try? JSONDecoder().decode(UserPrivate.self, from: Data(buffer: res.body))
            }
        }
        return result
    }
}
