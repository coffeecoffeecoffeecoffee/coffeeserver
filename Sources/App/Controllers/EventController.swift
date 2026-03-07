import Fluent
import Vapor

struct EventController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let eventsAPI = routes.grouped("api", "v2", "events")
        eventsAPI.get(use: index)
        eventsAPI.get("upcoming", use: future)
        eventsAPI.post(use: create)
        eventsAPI.group(":eventID") { event in
            event.put(use: update)
            event.delete(use: delete)
            event.get(use: fetchEvent)
        }
//        eventsAPI.post("bulk", use: bulkAddEvents)
        eventsAPI.on(.POST, "bulk", body: .collect(maxSize: 150_000), use: bulkAddEvents)
    }

    func index(req: Request) async throws -> [Event] {
        return try await Event.query(on: req.db)
            .sort(\.$endAt, .ascending)
            .all()
    }

    func future(req: Request) async throws -> [Event] {
        let now = Date.now
        return try await Event.query(on: req.db)
            .filter(\.$endAt, .greaterThan, now)
            .sort(\.$endAt, .ascending)
            .all()
    }

    func fetchEvent(req: Request) async throws -> Event {
        guard let eventIDString = req.parameters.get("eventID"),
            let eventID = UUID(eventIDString)
        else {
            throw Abort(.badRequest)
        }
        guard let event = try await Event.find(eventID, on: req.db) else {
            throw Abort(.notFound)
        }
        return event
    }

    func create(req: Request) async throws -> EventData {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized event creation\n\(req)")
            throw Abort(.unauthorized)
        }
        let eventData = try req.content.decode(EventData.self)
        
        let groupID = eventData.groupID
        let existingGroup = try await InterestGroup.find(groupID, on: req.db)
        
        guard let venueID = eventData.venue.id else {
            throw Abort(.badRequest, reason: "Venue ID is required")
        }
        let existingVenue = try await Venue.find(venueID, on: req.db)
        
        guard let interestGroup = existingGroup else {
            throw Abort(.notFound, reason: "No group with id \(groupID)")
        }
        guard let venue = existingVenue else {
            throw Abort(.notFound, reason: "No venue with id \(venueID)")
        }
        
        let existingGroupID = try interestGroup.requireID()
        let existingVenueID = try venue.requireID()
        
        let event = Event(
            id: eventData.id,
            name: eventData.name,
            short: eventData.short,
            group: existingGroupID,
            venue: existingVenueID,
            imageURL: eventData.imageURL,
            startAt: eventData.startAt,
            endAt: eventData.endAt,
            notes: eventData.notes
        )
        
        try await event.save(on: req.db)
        
        return try await event.publicData(db: req.db)
    }
    
    func update(req: Request) async throws -> EventData {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized Event edit request\n\(req)")
            throw Abort(.unauthorized)
        }
        guard let eventIDString = req.parameters.get("eventID"),
            let eventID = UUID(eventIDString)
        else {
            throw Abort(.badRequest)
        }
        let eventData = try req.content.decode(EventData.self)
        
        async let event = Event.find(eventID, on: req.db)
        async let group = InterestGroup.find(eventData.groupID, on: req.db)
        async let venue = Venue.find(eventData.venue.id, on: req.db)
        
        guard let event = try await event,
              let group = try await group,
              let venue = try await venue else {
            throw Abort(.notFound)
        }
        event.name = eventData.name
        event.startAt = eventData.startAt
        event.endAt = eventData.endAt
        event.$group.id = try group.requireID()
        event.$venue.id = try venue.requireID()
        event.imageURL = eventData.imageURL
        event.notes = eventData.notes
        event.short = eventData.short ?? eventData.name.toSlug()
        try await event.update(on: req.db)
        return try await event.publicData(db: req.db)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized Event delete request\n\(req)")
            throw Abort(.unauthorized)
        }
        guard let eventIDString = req.parameters.get("eventID"),
            let eventID = UUID(eventIDString)
        else {
            throw Abort(.badRequest)
        }
        guard let event = try await Event.find(eventID, on: req.db) else {
            throw Abort(.notFound)
        }
        try await event.delete(on: req.db)
        return .noContent
    }
    
    
    func bulkAddEvents(req: Request) async throws -> HTTPStatus {
        guard let isAdmin = try? await req.isAdmin(), isAdmin else {
            throw Abort(.unauthorized)
        }
        let events = try req.content.decode([EventData].self)
        for newEvent in events {
            try await newEvent.saveAsEvent(on: req.db)
        }
        return .created
    }
}
