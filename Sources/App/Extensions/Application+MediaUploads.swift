//
//  Application+MediaUploads.swift
//  CoffeeServer
//

import Vapor

/// Where uploaded media is stored and how large an upload may be.
struct MediaUploadConfiguration: Sendable {
    static let defaultMaxUploadSize: Int64 = 1024 * 1024 * 1024

    /// Directory uploaded files are written to
    var directoryPath: String
    /// Largest accepted upload, in bytes
    var maxUploadSize: Int64

    init(directoryPath: String, maxUploadSize: Int64 = defaultMaxUploadSize) {
        self.directoryPath = directoryPath
        self.maxUploadSize = maxUploadSize
    }
}

extension Application {
    private struct MediaUploadConfigurationKey: StorageKey {
        typealias Value = MediaUploadConfiguration
    }

    /// Media upload settings used when routes are registered.
    ///
    /// Defaults to `Public/media` with a 1 GB limit. Set it before calling `configure(_:)` to override,
    /// for example to point tests at a temporary directory with a small limit.
    var mediaUploads: MediaUploadConfiguration {
        get {
            storage[MediaUploadConfigurationKey.self]
                ?? MediaUploadConfiguration(directoryPath: directory.publicDirectory.appending("media"))
        }
        set {
            storage[MediaUploadConfigurationKey.self] = newValue
        }
    }
}
