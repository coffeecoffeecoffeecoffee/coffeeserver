import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("User Delete Tests")
struct UserDeleteTests {

    let password = "Just a regular password 1"

    @Test("Admin deletes a user who has tags")
    func adminDeletesTaggedUser() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            let user = try await makeUser(app: app, email: "tagged@example.com", tags: ["barista", "regular"])
            let userID = try user.requireID()

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(userID)",
                headers: ["Authorization": "Bearer \(adminJWT)"]
            ) { res async in
                #expect(res.status == .noContent)
            }

            #expect(try await User.find(userID, on: app.db) == nil, "User is deleted")
            let links = try await UserTag.query(on: app.db).filter(\.$user.$id == userID).count()
            #expect(links == 0, "Tag links are removed")
            #expect(try await App.Tag.query(on: app.db).filter(\.$name == "barista").count() == 1, "Tags themselves remain")
        }
    }

    @Test("User with tags deletes themselves")
    func taggedUserSelfDeletes() async throws {
        try await withApp(configure: configure) { app in
            let user = try await makeUser(app: app, email: "self@example.com", tags: ["regular"])
            let userID = try user.requireID()
            let userJWT = try await login(app: app, email: user.email, password: password)

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(userID)",
                headers: ["Authorization": "Bearer \(userJWT)"]
            ) { res async in
                #expect(res.status == .noContent)
            }

            #expect(try await User.find(userID, on: app.db) == nil, "User is deleted")
        }
    }

    @Test("Admin cannot delete another admin")
    func adminCannotDeleteAdmin() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            let otherAdmin = try await makeUser(app: app, email: "other-admin@example.com", tags: ["admin"])
            let otherAdminID = try otherAdmin.requireID()

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(otherAdminID)",
                headers: ["Authorization": "Bearer \(adminJWT)"]
            ) { res async in
                #expect(res.status == .forbidden)
            }

            let remaining = try #require(try await User.find(otherAdminID, on: app.db), "Admin is not deleted")
            #expect(try await remaining.$tags.get(on: app.db).map(\.name) == ["admin"], "Admin keeps the admin tag")
        }
    }

    @Test("Admin cannot delete themselves")
    func adminCannotSelfDelete() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            let adminEmail = try #require(Environment.get("SERVER_ADMIN_EMAIL"))
            let admin = try #require(try await User.query(on: app.db).filter(\.$email == adminEmail).first())
            let adminID = try admin.requireID()

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(adminID)",
                headers: ["Authorization": "Bearer \(adminJWT)"]
            ) { res async in
                #expect(res.status == .forbidden)
            }

            #expect(try await User.find(adminID, on: app.db) != nil, "Admin is not deleted")
        }
    }

    @Test("Non-admin cannot delete another user")
    func nonAdminCannotDeleteOthers() async throws {
        try await withApp(configure: configure) { app in
            let requester = try await makeUser(app: app, email: "requester@example.com", tags: [])
            let target = try await makeUser(app: app, email: "target@example.com", tags: ["regular"])
            let targetID = try target.requireID()
            let requesterJWT = try await login(app: app, email: requester.email, password: password)

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(targetID)",
                headers: ["Authorization": "Bearer \(requesterJWT)"]
            ) { res async in
                #expect(res.status == .unauthorized)
            }

            #expect(try await User.find(targetID, on: app.db) != nil, "Target is not deleted")
        }
    }

    // MARK: - Helpers

    /// Saves a user with `password`, attaching tags by name and creating any that don't exist.
    private func makeUser(app: Application, email: String, tags tagNames: [String]) async throws -> User {
        let user = try User(name: email, email: email, passwordHash: Bcrypt.hash(password))
        try await user.save(on: app.db)
        for name in tagNames {
            let tag: App.Tag
            if let existing = try await App.Tag.query(on: app.db).filter(\.$name == name).first() {
                tag = existing
            } else {
                tag = App.Tag(name: name)
                try await tag.save(on: app.db)
            }
            try await user.$tags.attach(tag, on: app.db)
        }
        return user
    }
}
