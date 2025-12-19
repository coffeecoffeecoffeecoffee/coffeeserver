import Fluent
import ICalendarKit
import Vapor

extension InterestGroupController {
    func calendar(_ req: Request) async throws -> some AsyncResponseEncodable {
        guard let groupIDString = req.parameters.get("groupID"),
              let groupID = UUID(groupIDString) else {
            throw Abort(.badRequest)
        }
        guard let group = try await InterestGroup.find(groupID, on: req.db) else {
            throw Abort(.notFound)
        }
        // Optimization: 50 events should be roughtly a year of events.
        let events = try await group.$events.query(on: req.db)
            .with(\.$venue)
            .limit(50)
            .all()
        let iCalEvents = try await icalEvents(for: events, req: req)
        let calendarBody = ICalendar(events: iCalEvents).vEncoded
        let calHeaders = calendarHeaders(group: group)
        let response = Response(status: .ok,
                                headers: calHeaders,
                                body: .init(stringLiteral: calendarBody)
        )
        return response
    }
    
    private func calendarHeaders(group: InterestGroup) -> HTTPHeaders {
        let percentEncodedGroupName: String = group.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "Calendar"
        let headers = HTTPHeaders(dictionaryLiteral:
                                    ("Content-Type", "text/calendar"),
                                  ("Content-Disposition", "attachment; filename=\"\(group.name).ics\"; filename*=UTF-8''\(percentEncodedGroupName).ics")
        )
        return headers
    }
    
    private func icalEvents(for events: [Event], req: Request) async throws -> [ICalendarEvent] {
        var icEvents = [ICalendarEvent]()
        for event in events {
            var icEvent = ICalendarEvent(dtstamp: Date(),
                                         uid: event.id!.uuidString,
                                         description: "See you there!",
                                         dtstart: .dateTime(event.startAt),
                                         summary: event.name,
                                         dtend: .dateTime(event.endAt),
                                         duration: nil,
                                         xMicrosoftCDOBusyStatus: .busy)
            let venue = event.venue
            icEvent.description = "Coffee at \(venue.name)\n\n\(venue.location?.mapLocation ?? venue.location?.title ?? "")"
            icEvent.location = venue.location?.address ?? venue.location?.mapLocation ?? venue.location?.title ?? ""
            if let lat = venue.location?.latitude,
               let lon = venue.location?.longitude {
                icEvent.geo = .init(latitude: lat, longitude: lon)
            }
            icEvents.append(icEvent)
        }
        let sortedEvents = icEvents.sorted(by: { $0 < $1 })
        return sortedEvents
    }
}

extension ICalendarEvent: @retroactive Equatable {}
extension ICalendarEvent: @retroactive Comparable {
    public static func < (lhs: ICalendarKit.ICalendarEvent, rhs: ICalendarKit.ICalendarEvent) -> Bool {
        guard let lhsStart = lhs.dtstart,
              let rhsStart = rhs.dtstart else {
            return false
        }
        return lhsStart < rhsStart
    }
    public static func == (lhs: ICalendarKit.ICalendarEvent, rhs: ICalendarKit.ICalendarEvent) -> Bool {
        lhs.dtstart == rhs.dtstart
    }
}

extension ICalendarDate: @retroactive Equatable {}
extension ICalendarDate: @retroactive Comparable {
    public static func < (lhs: ICalendarKit.ICalendarDate, rhs: ICalendarKit.ICalendarDate) -> Bool {
        lhs.date < rhs.date
    }
    public static func == (lhs: ICalendarDate, rhs: ICalendarDate) -> Bool {
        lhs.date == rhs.date
    }
}

