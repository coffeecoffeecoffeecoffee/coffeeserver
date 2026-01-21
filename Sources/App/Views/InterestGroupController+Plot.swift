import CoffeeKit
import Fluent
import Plot
import Vapor

extension InterestGroup: Hashable, Equatable {
    static func == (lhs: InterestGroup, rhs: InterestGroup) -> Bool {
        lhs.name == rhs.name
    }
    
    func hash(into hasher: inout Hasher) {
        self.name.hash(into: &hasher)
    }
}

// MARK: - WebView
extension InterestGroupController {
    
    public func interestGroupsAndEvents(req: Request) async throws -> [(InterestGroup, [EventData])] {
        let now = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let allGroups = try await InterestGroup.query(on: req.db)
            .filter(\.$isArchived == false)
            .with(\.$events)
            .all()
            .sorted { prevGroup, thisGroup in
                if let prevStart = prevGroup.events.map(\.startAt).max(),
                   let thisStart = thisGroup.events.map(\.startAt).max() {
                    return prevStart > thisStart
                }
                return false
            }
        let groupEvents: [(InterestGroup, [EventData])] = try await withThrowingTaskGroup(
            of: [(InterestGroup, [EventData])].self
        ) { taskGroup in
            var rawGroupsAndEvents = [(InterestGroup, [EventData])]()
            for interestGroup in allGroups {
                taskGroup.addTask {
                    let eventModels = try await interestGroup
                        .$events
                        .query(on: req.db)
                        .filter(\Event.$endAt >= now)
                        .sort(\.$startAt)
                        .all()
                    // TODO: Update this to one query. It can be done!
                    //                        .with(\.$venue)
                    
                    var eventDatas = [EventData]()
                    for eventModel in eventModels {
                        guard let eventData = try? await eventModel.publicData(db: req.db) else {
                            req.logger
                                .error(
                                    "Couldn’t get public data for event: \(eventModel.id?.uuidString ?? eventModel.name)"
                                )
                            continue
                        }
                        eventDatas.append(eventData)
                    }
                    return [(interestGroup, eventDatas)]
                }
            }
            for try await element in taskGroup {
                rawGroupsAndEvents.append(contentsOf: element)
            }
            let sortedGroupEvents = rawGroupsAndEvents.sorted { alpha, bravo in
                guard let alphaMostRecentEvent = alpha.1.first?.endAt,
                      let bravoMostRecentEvent = bravo.1.first?.endAt else { return false }
                return alphaMostRecentEvent < bravoMostRecentEvent
            }
            return sortedGroupEvents
        }
        
        return groupEvents
    }
    
    func webView(req: Request) async throws -> Response {
        let sortedGroupEvents = try await interestGroupsAndEvents(req: req)
        guard sortedGroupEvents.count > 0 else {
            return WebPage(NoGroupsView()).response()
        }
        let list = Div {
            Header {
                H1("Coffee Coffee Coffee Coffee")
                    .class("hidden")
                Image("/logo-stack.png")
                    .class("header-image")
            }
            Div {
                for (group, events) in sortedGroupEvents {
                    GroupView(group: group, events: events)
                }
            }
            .id("coffee-groups")
        }
        .class("wrapper")
        return WebPage(list).response()
    }
    
    
    private func calendarURLString(_ hostName: String, groupID: UUID) -> String {
        return "webcal://\(hostName)/groups/\(groupID.uuidString)/calendar.ics"
    }
    
    func webViewSingle(req: Request) async throws -> Response {
        let now = Date.now
        let group = try await fetch(req: req)
        let futureEvents = try await group.$events
            .query(on: req.db)
            .sort(\.$startAt, .ascending)
            .filter(\.$endAt > now)
            .with(\.$venue)
            .all()
        let pastEvents = try await group.$events
            .query(on: req.db)
            .sort(\.$endAt, .descending)
            .filter(\.$endAt <= now)
            .with(\.$venue)
            .limit(100)
            .all()
        
        let content = Div {
            Header {
                Link(url: "/") {
                    Image(url: "/logo-long.png", description: "Home")
                        .class("header-image")
                }
                
                H1(group.name)
                if let groupID = try? group.requireID(),
                   let hostName = req.headerHostName() {
                    Link(url: calendarURLString(hostName, groupID: groupID)) {
                        Image("/icon-calendar.png")
                        Text("Subscribe to Calendar")
                    }
                    .class("white-button")
                }
            }
            Div {
                if futureEvents.count > 0 {
                    H2("Upcoming")
                    for event in futureEvents {
                        coffeeEventView(event)
                    }
                } else {
                    H2("No coffee events scheduled")
                }
                if pastEvents.count > 0 {
                    H2("Previously")
                    for event in pastEvents {
                        coffeeEventView(event)
                    }
                }
            }.id("coffee-groups")
        }
        
        return WebPage(content).response(
            title: group.name,
            ogPath: req.headerHostName()?.appending(group.short),
            ogImagePath: group.imageURL
        )
    }
    
    private func location(for event: Event) -> String {
        let venue = event.venue
        if let mapsURL = venue.url {
            return mapsURL
        } else if let mapsLocation = venue.location?.mapLocation {
            return mapsLocation
        } else if let location = venue.location,
                  let lat = location.latitude,
                  let lon = location.longitude {
            return "maps://maps.apple.com/?q=\(venue.name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? venue.name)&coordinate=\(lat),\(lon)"
        } else {
            return "#"
        }
    }

    func coffeeEventView(_ event: Event) -> any Component {
        Div {
            Link(url: location(for: event), label: {
                Div {
                    H2(event.name)
                    Div {
                        Div {
                            Paragraph(
                                event.startAt.formattedWith(timeStyle: .short)
                            )
                            H4(event.venue.name)
                            if let locationDescription = event.venue.location?.title {
                                Div {
                                    Span(locationDescription)
                                    // TODO: Sort this out in the UI later
                                    // Span("Directions")
                                }
                                .class("location-description")
                            }
                        }.class("details")
                    }.class("bar")
                }.class("event")
                    .style("""
                    background-image: linear-gradient(
                        0deg, 
                        rgba(2, 0, 36, 0.5) 0%, 
                        rgba(1, 0, 18, 0.0) 75%,
                        rgba(1, 0, 18, 0.0) 85%,
                        rgba(2, 0, 36, 0.8) 100%
                    ),
                    url('\(event.imageURL ?? "/default-coffee.webp")');
                    background-size: cover;
                """)
            })
        }.class("coffee-group")
    }
}
