//
//  MediaContentController.swift
//  CoffeeServer
//
//  Created by Michael Critz on 11/9/25.
//

import Fluent
import NIOCore
import Vapor

final class MediaContentController: Sendable, RouteCollection {
    // req.application.directory.resourcesDirectory.appending("media")
    private let mediaDirectoryPath: String
    private let maxUploadSize: Int64 = 1024 * 1024 * 1024

    init(mediaPath: String) {
        self.mediaDirectoryPath = mediaPath
    }

    func boot(routes: Vapor.RoutesBuilder) throws {
        let mediaAPI = routes.grouped("api", "v2", "media")
        mediaAPI.on(.POST, "upload", body: .stream, use: uploadMedia)
        mediaAPI.group(":mediaID") { mediaItem in
            mediaItem.get(use: getMedia)
        }
    }
    
    func getMedia(req: Request) async throws -> Response {
        guard let mediaID = req.parameters.get("mediaID") else {
            throw Abort(.badRequest, reason: "No media ID provided")
        }
        guard let mediaID = UUID(mediaID),
            let userMedia = try await MediaContent.find(mediaID, on: req.db)
        else {
            throw Abort(.notFound)
        }
        let filePath = mediaDirectoryPath.appending("/\(userMedia.filename)")
        
        guard let mediaType = userMedia.mediaType() else {
            return req.fileio.streamFile(at: filePath)
        }
        return req.fileio.streamFile(at: filePath, mediaType: mediaType)
    }
    
    func uploadMedia(req: Request) async throws -> MediaContent {
        let payload = try req.jwt.verify(as: SessionJWTToken.self)
        guard let requestingUser = try await User.find(payload.userId, on: req.db) else {
            req.logger.info("Unauthorized upload attempt:\n\(req)")
            throw Abort(.unauthorized, reason: "Must be logged in")
        }
        return try await storeUpload(req: req, uploader: requestingUser)
    }

    /// Streams the request body to the media directory and saves a ``MediaContent`` record for it.
    /// - Parameters:
    ///   - req: Request with `File-Name` and `Content-Type` headers and a streamed body
    ///   - uploader: the ``User`` who owns the upload
    ///   - venue: optional ``Venue`` to associate the media with
    /// - Returns: the saved ``MediaContent``
    func storeUpload(req: Request, uploader: User, venue: Venue? = nil) async throws -> MediaContent {
        guard let rawFilename = req.headers["File-Name"].first else {
            throw Abort(.badRequest, reason: "File-Name header missing or invalid")
        }
        // TODO: We really shouldn’t trust users with honest `Content-Type`s. Even if they aren’t malicious, they’re
        // busy and forgetful. This could lead to serious problems. For now, we can mitigate that this functionality
        // should be limited in its usefulness to authorized users. But still...
        guard let contentType = req.headers["Content-Type"].first else {
            throw Abort(.badRequest, reason: "Content-Type header is missing")
        }

        do {
            try FileManager.default.createDirectory(
                atPath: mediaDirectoryPath,
                withIntermediateDirectories: true
            )
        } catch {
            req.logger.error("Failed to create media directory: \(String(describing: error))")
            throw Abort(.internalServerError, reason: "Server misconfigured for file uploads")
        }
        let filename = UUID().uuidString
        let filePath = mediaDirectoryPath.appending("/\(filename)")
        try? FileManager.default.removeItem(atPath: filePath)
        guard FileManager.default.createFile(atPath: filePath,
                                       contents: nil,
                                       attributes: nil) else {
            req.logger.error("File creation failed for:\n\t \(filePath)")
            throw Abort(.internalServerError)
        }
        
        // Any failure from here on removes the file, so a failed upload never leaves an
        // orphaned file in the media directory or a record pointing at a truncated one.
        do {
            let streamedLength = try await streamBody(of: req, toFileAt: filePath)
            let media = try MediaContent(
                filename: filename,
                rawFilename: rawFilename,
                mimeType: contentType,
                contentLength: Int(streamedLength),
                userID: uploader,
                venue: venue
            )
            try await media.save(on: req.db)
            return media
        } catch {
            do {
                try FileManager.default.removeItem(atPath: filePath)
            } catch let cleanupError {
                req.logger.error("Failed to remove incomplete upload at \(filePath): \(String(describing: cleanupError))")
            }
            throw error
        }
    }

    /// Writes the streamed request body to `filePath`, enforcing ``maxUploadSize``.
    /// - Returns: the number of bytes written
    /// - Throws: `Abort(.badRequest)` if the body exceeds ``maxUploadSize``, or any write error
    private func streamBody(of req: Request, toFileAt filePath: String) async throws -> Int64 {
        let nioFileHandle = try NIOFileHandle(path: filePath, mode: .write)
        defer {
            do {
                try nioFileHandle.close()
            } catch {
                req.logger.error("\(error.localizedDescription)")
            }
        }

        var streamedLength: Int64 = 0
        for try await byteBuffer in req.body {
            let chunkLength = Int64(byteBuffer.readableBytes)
            guard streamedLength + chunkLength <= maxUploadSize else {
                throw Abort(.badRequest, reason: "Upload exceeds maximum")
            }
            try await req.application.fileio.write(fileHandle: nioFileHandle,
                                                   toOffset: streamedLength,
                                                   buffer: byteBuffer,
                                                   eventLoop: req.eventLoop).get()
            streamedLength += chunkLength
        }
        return streamedLength
    }
}
