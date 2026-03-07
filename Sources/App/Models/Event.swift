import CoffeeKit
import Fluent
import Vapor

public typealias ImageURL = String

final class Event: EventRepresentable, Model, Content, @unchecked Sendable {
    static let schema = "events"
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String
    
    @Parent(key: "group_id")
    var group: InterestGroup
    
    @Parent(key: "venue_id")
    var venue: Venue
    
    @Field(key: "image_url")
    var imageURL: ImageURL?
    
    @Field(key: "start_at")
    var startAt: Date
    
    @Field(key: "end_at")
    var endAt: Date

    @Field(key: "short")
    var short: String?

    @Field(key: "notes")
    var notes: String?
    
    init() { }

    init(id: UUID? = nil,
         name: String,
         short: String? = nil,
         group: InterestGroup.IDValue,
         venue: Venue.IDValue,
         imageURL: ImageURL? = nil,
         startAt: Date,
         endAt: Date,
         notes: String? = nil) {
        self.id = id
        self.name = name
        self.short = short ?? name.toSlug()
        self.$group.id = group
        self.$venue.id = venue
        self.imageURL = imageURL
        self.startAt = startAt
        self.endAt = endAt
        self.notes = notes
    }
}

extension Event: Hashable {
    // Hashable requires Equatable
    static func == (lhs: Event, rhs: Event) -> Bool {
        guard let lhsID = try? lhs.requireID(),
              let rhsID = try? rhs.requireID() else {
            return false
        }
        return lhsID == rhsID
    }

    func hash(into hasher: inout Hasher) {
        if let id = try? self.requireID() {
            hasher.combine(id)
        }
    }
}

extension Event {
    func publicData(db: Database) async throws -> EventData {
        let groupID = try await self.$group.get(on: db).requireID()
        let venue = try await self.$venue.get(on: db)
        return .init(id: self.id,
                     name: self.name,
                     short: self.short,
                     groupID: groupID,
                     venue: venue,
                     imageURL: self.imageURL,
                     startAt: self.startAt,
                     endAt: self.endAt,
                     notes: self.notes)
    }
}
