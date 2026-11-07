import Fluent
import Foundation
import Testing
import VaporTesting

@testable import App

@Suite("Media Upload Tests")
struct MediaUploadTests {

    /// Small enough to test the boundary with a handful of bytes.
    let uploadLimit: Int64 = 16

    @Test("An upload exactly at the size limit is accepted")
    func uploadAtLimitAccepted() async throws {
        let body = Data(repeating: 0x2A, count: Int(uploadLimit))
        try await withMediaApp { app, mediaDirectory in
            let adminJWT = try await loginAsAdmin(app: app)

            var uploaded: MediaContent?
            try await app.testing().test(
                .POST, "/api/v2/media/upload",
                headers: uploadHeaders(jwt: adminJWT),
                body: ByteBuffer(data: body)
            ) { res async in
                #expect(res.status == .ok)
                uploaded = try? JSONDecoder().decode(MediaContent.self, from: Data(buffer: res.body))
            }

            let media = try #require(uploaded)
            #expect(media.contentLength == body.count)
            #expect(try files(in: mediaDirectory) == [media.filename], "Only the uploaded file is written")
            let written = try Data(contentsOf: URL(fileURLWithPath: mediaDirectory).appendingPathComponent(media.filename))
            #expect(written == body, "File on disk matches the upload")
        }
    }

    @Test("An upload one byte over the size limit is rejected and leaves nothing behind")
    func uploadOverLimitRejected() async throws {
        let body = Data(repeating: 0x2A, count: Int(uploadLimit) + 1)
        try await withMediaApp { app, mediaDirectory in
            let adminJWT = try await loginAsAdmin(app: app)

            try await app.testing().test(
                .POST, "/api/v2/media/upload",
                headers: uploadHeaders(jwt: adminJWT),
                body: ByteBuffer(data: body)
            ) { res async in
                #expect(res.status == .badRequest)
            }

            #expect(try await MediaContent.query(on: app.db).count() == 0, "No record is saved")
            #expect(try files(in: mediaDirectory).isEmpty, "The partial file is removed")
        }
    }

    @Test("A failed record save removes the uploaded file")
    func failedSaveRemovesFile() async throws {
        try await withMediaApp { app, mediaDirectory in
            let adminJWT = try await loginAsAdmin(app: app)
            // Make `media.save(on:)` fail after the body has been written to disk.
            try await app.db.schema(MediaContent.schema).delete()

            try await app.testing().test(
                .POST, "/api/v2/media/upload",
                headers: uploadHeaders(jwt: adminJWT),
                body: ByteBuffer(data: Data("small".utf8))
            ) { res async in
                #expect(res.status == .internalServerError)
            }

            #expect(try files(in: mediaDirectory).isEmpty, "The written file is removed")
        }
    }

    // MARK: - Helpers

    /// Runs `test` against an app whose uploads go to a fresh temporary directory with ``uploadLimit``.
    private func withMediaApp(
        _ test: (Application, String) async throws -> Void
    ) async throws {
        let mediaDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoffeeServerTests-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: mediaDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: mediaDirectory) }

        let limit = uploadLimit
        try await withApp(configure: { app in
            app.mediaUploads = MediaUploadConfiguration(directoryPath: mediaDirectory, maxUploadSize: limit)
            try configure(app)
        }) { app in
            try await test(app, mediaDirectory)
        }
    }

    private func uploadHeaders(jwt: String) -> HTTPHeaders {
        [
            "Authorization": "Bearer \(jwt)",
            "File-Name": "upload.bin",
            "Content-Type": "application/octet-stream",
        ]
    }

    private func files(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory)
    }
}
