import Fluent
import Vapor

final class VenueController: RouteCollection {
    private let mediaContentController: MediaContentController

    init(mediaContentController: MediaContentController) {
        self.mediaContentController = mediaContentController
    }

    func boot(routes: Vapor.RoutesBuilder) throws {
        let venuesAPI = routes.grouped("api", "v2", "venues")
        venuesAPI.get(use: index)
        venuesAPI.post(use: create)
        venuesAPI.group(":venueID") { venue in
            venue.get(use: fetchVenue)
            venue.put(use: updateVenue)
            venue.delete(use: deleteVenue)
            venue.get("events", use: venueEvents)
            venue.get("media", use: venueMedia)
            venue.on(.POST, "media", body: .stream, use: uploadVenueMedia)
        }
    }
    
    func index(req: Request) async throws -> [Venue] {
        try await Venue.query(on: req.db).all()
    }
    
    func create(req: Request) async throws -> Venue {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized venue creation attempt")
            throw Abort(.unauthorized)
        }
        let venue = try req.content.decode(Venue.self)
        try await venue.save(on: req.db)
        return venue
    }
    
    func fetchVenue(req: Request) async throws -> Venue {
        guard let venueIDString = req.parameters.get("venueID"),
        let venueID = UUID(venueIDString) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        return venue
    }
    
    func updateVenue(req: Request) async throws -> Venue {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized Venue update attempt")
            throw Abort(.unauthorized)
        }
        guard let venueIDString = req.parameters.get("venueID"),
              let venueID = UUID(venueIDString),
              let newVenue = try? req.content.decode(Venue.self) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        venue.name = newVenue.name
        venue.location = newVenue.location
        venue.url = newVenue.url
        try await venue.update(on: req.db)
        return venue
    }
    
    func deleteVenue(req: Request) async throws -> HTTPStatus {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized Venue delete attempt")
            throw Abort(.unauthorized)
        }
        guard let venueIDString = req.parameters.get("venueID"),
        let venueID = UUID(venueIDString) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        try await venue.delete(on: req.db)
        return .noContent
    }
    
    func venueEvents(req: Request) async throws -> [EventData] {
        guard let venueIDString = req.parameters.get("venueID"),
        let venueID = UUID(venueIDString) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        let eventsSortedByStartTime = try await venue.$events.get(on: req.db).sorted(by: {
            $0.startAt < $1.startAt
        })
        var publicEvents = [EventData]()
        for venueEvent in eventsSortedByStartTime {
            guard let thisEvent = try? await venueEvent.publicData(db: req.db) else {
                req.logger.error(
                    "Failed to serialize Event for public listing: \(venueEvent.id?.uuidString ?? venueEvent.name)"
                )
                continue
            }
            publicEvents.append(thisEvent)
        }
        return publicEvents
    }
    
    func venueMedia(req: Request) async throws -> [MediaContent] {
        guard let venueIDString = req.parameters.get("venueID"),
        let venueID = UUID(venueIDString) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        return try await venue.$media.get(on: req.db)
    }
    
    func uploadVenueMedia(req: Request) async throws -> MediaContent {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized Venue media upload attempt")
            throw Abort(.unauthorized)
        }
        guard let venueIDString = req.parameters.get("venueID"),
        let venueID = UUID(venueIDString) else {
            throw Abort(.badRequest)
        }
        guard let venue = try await Venue.find(venueID, on: req.db) else {
            throw Abort(.notFound)
        }
        let payload = try req.jwt.verify(as: SessionJWTToken.self)
        guard let uploader = try await User.find(payload.userId, on: req.db) else {
            throw Abort(.unauthorized)
        }
        return try await mediaContentController.storeUpload(req: req, uploader: uploader, venue: venue)
    }
}
