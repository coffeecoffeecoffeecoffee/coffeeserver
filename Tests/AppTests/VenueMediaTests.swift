import CoffeeKit
import Fluent
import Testing
import VaporTesting

@testable import App

@Suite("Venue Media Tests")
struct VenueMediaTests {

    let imageBytes = Data("not really a png".utf8)

    @Test("Admin uploads media to a Venue and retrieves it")
    func uploadAndRetrieveVenueMedia() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await login(
                app: app,
                email: try #require(Environment.get("SERVER_ADMIN_EMAIL")),
                password: try #require(Environment.get("SERVER_ADMIN_PASSWORD"))
            )
            let venue = Venue(name: "Blue Bottle")
            try await venue.save(on: app.db)
            let venueID = try venue.requireID()

            var uploaded: MediaContent?
            try await app.testing().test(
                .POST,
                "/api/v2/venues/\(venueID)/media",
                headers: [
                    "Authorization": "Bearer \(adminJWT)",
                    "File-Name": "storefront.png",
                    "Content-Type": "image/png",
                ],
                body: ByteBuffer(data: imageBytes)
            ) { res async in
                #expect(res.status == .ok, "Admin can upload Venue media")
                uploaded = try? JSONDecoder().decode(MediaContent.self, from: Data(buffer: res.body))
            }
            let media = try #require(uploaded)
            let mediaID = try media.requireID()
            defer {
                try? FileManager.default.removeItem(
                    atPath: app.directory.publicDirectory.appending("media/\(media.filename)")
                )
            }
            #expect(media.rawFilename == "storefront.png")
            #expect(media.mimeType == "image/png")
            #expect(media.contentLength == imageBytes.count)
            #expect(media.$venue.id == venueID, "Media is associated with the Venue")

            try await app.testing().test(.GET, "/api/v2/venues/\(venueID)/media") { res async in
                #expect(res.status == .ok)
                let list = try? JSONDecoder().decode([MediaContent].self, from: Data(buffer: res.body))
                #expect(list?.map(\.id) == [mediaID], "Venue media list includes the upload")
            }

            try await app.testing().test(.GET, "/api/v2/media/\(mediaID)") { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType == .png)
                #expect(Data(buffer: res.body) == imageBytes, "Media bytes round-trip")
            }
        }
    }

    @Test("Non-admin cannot upload Venue media")
    func nonAdminUploadRejected() async throws {
        try await withApp(configure: configure) { app in
            let user = UserCreate(
                name: "Regular Person",
                email: "regular@example.com",
                password: "Just a regular password 1",
                confirmPassword: "Just a regular password 1"
            )
            try await app.testing().test(
                .POST,
                "/api/v2/users",
                headers: ["Content-Type": "application/json"],
                body: ByteBuffer(data: try JSONEncoder().encode(user))
            ) { res async in
                #expect(res.status == .created)
            }
            let userJWT = try await login(app: app, email: user.email, password: user.password)
            let venue = Venue(name: "Ritual")
            try await venue.save(on: app.db)
            let venueID = try venue.requireID()

            try await app.testing().test(
                .POST,
                "/api/v2/venues/\(venueID)/media",
                headers: [
                    "Authorization": "Bearer \(userJWT)",
                    "File-Name": "storefront.png",
                    "Content-Type": "image/png",
                ],
                body: ByteBuffer(data: imageBytes)
            ) { res async in
                #expect(res.status == .unauthorized)
            }
            let count = try await MediaContent.query(on: app.db).count()
            #expect(count == 0, "No media is saved for a rejected upload")
        }
    }

    @Test("Venue media for an unknown Venue is not found")
    func unknownVenueMedia() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "/api/v2/venues/\(UUID())/media") { res async in
                #expect(res.status == .notFound)
            }
        }
    }

    private func login(app: Application, email: String, password: String) async throws -> String {
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
}
