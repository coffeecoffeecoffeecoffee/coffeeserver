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

    @Test("Admin deleting a user with uploads takes ownership of them")
    func adminDeleteHandsMediaToAdmin() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            let admin = try await serverAdminUser(app: app)
            let user = try await makeUser(app: app, email: "uploader@example.com", tags: ["regular"])
            let userID = try user.requireID()
            let (mediaID, linkID) = try await makeUpload(app: app, owner: user)

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(userID)",
                headers: ["Authorization": "Bearer \(adminJWT)"]
            ) { res async in
                #expect(res.status == .noContent)
            }

            #expect(try await User.find(userID, on: app.db) == nil, "User is deleted")
            let media = try #require(try await MediaContent.find(mediaID, on: app.db), "Upload is kept")
            #expect(media.$user.id == admin.id, "Upload now belongs to the deleting admin")
            let link = try #require(try await UserMediaContent.find(linkID, on: app.db), "Media link is kept")
            #expect(link.$user.id == admin.id, "Media link now points to the deleting admin")
        }
    }

    @Test("User with uploads deletes themselves and the server admin takes ownership")
    func selfDeleteHandsMediaToServerAdmin() async throws {
        try await withApp(configure: configure) { app in
            let admin = try await serverAdminUser(app: app)
            let user = try await makeUser(app: app, email: "self-uploader@example.com", tags: [])
            let userID = try user.requireID()
            let (mediaID, _) = try await makeUpload(app: app, owner: user)
            let userJWT = try await login(app: app, email: user.email, password: password)

            try await app.testing().test(
                .DELETE, "/api/v2/users/\(userID)",
                headers: ["Authorization": "Bearer \(userJWT)"]
            ) { res async in
                #expect(res.status == .noContent)
            }

            #expect(try await User.find(userID, on: app.db) == nil, "User is deleted")
            let media = try #require(try await MediaContent.find(mediaID, on: app.db), "Upload is kept")
            #expect(media.$user.id == admin.id, "Upload now belongs to the server admin")
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

    private func serverAdminUser(app: Application) async throws -> User {
        let adminEmail = try #require(Environment.get("SERVER_ADMIN_EMAIL"))
        return try #require(try await User.query(on: app.db).filter(\.$email == adminEmail).first())
    }

    /// Saves a media record owned by `owner` plus its user–media link. No file is written.
    private func makeUpload(app: Application, owner: User) async throws -> (media: UUID, link: UUID) {
        let media = try MediaContent(
            filename: UUID().uuidString,
            rawFilename: "photo.png",
            mimeType: "image/png",
            contentLength: 4,
            userID: owner
        )
        try await media.save(on: app.db)
        let link = try UserMediaContent(user: owner, mediaContent: media)
        try await link.save(on: app.db)
        return (try media.requireID(), try link.requireID())
    }
}
