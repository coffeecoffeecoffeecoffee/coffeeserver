import CoffeeKit
import Fluent
import Vapor

struct EventData: EventRepresentable, Codable {
    var id: UUID?
    var name: String
    var groupID: UUID
    var venue: Venue
    var imageURL: ImageURL?
    var startAt: Date
    var endAt: Date
    var notes: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case name
        case imageURL = "image_url"
        case startAt = "start_at"
        case endAt = "end_at"
        case venue
        case notes
    }
}

extension EventData: Content { }

extension EventData: AsyncResponseEncodable {
    func encodeResponse(for request: Vapor.Request) async throws -> Vapor.Response {
        let body = try JSONEncoder().encode(self)
        let jsonHeader = HTTPHeaders.init(dictionaryLiteral: ("Content-Type", "application/json"))
        return Response(headers: jsonHeader, body: .init(data: body))
    }
}

extension EventData {
    
    
    @discardableResult
    func saveAsEvent(on db: Database) async throws -> Event {
        guard let group = try await InterestGroup.find(self.groupID, on: db) else {
            throw Abort(.internalServerError, reason: "Invalid Group ID for \(name)")
        }
        
        // Venue: find existing or create a new one
        var thisVenue: Venue!
        if let existingVenue = try await venue.fetchFromModel(on: db) {
            thisVenue = existingVenue
        } else {
            try await venue.save(on: db)
            thisVenue = venue
        }
        
        
        let newEvent = Event(
            id: id,
            name: name,
            group: try group.requireID(),
            venue: try thisVenue.requireID(),
            imageURL: imageURL,
            startAt: startAt,
            endAt: endAt,
            notes: notes
        )
        try await newEvent.save(on: db)
        return newEvent
    }
}
