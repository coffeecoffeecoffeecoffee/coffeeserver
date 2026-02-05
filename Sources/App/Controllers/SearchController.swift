//
//  SearchController.swift
//  CoffeeServer
//
//  Created by Michael Critz on 2/3/26.
//

import CoffeeKit
import Fluent
import Vapor

struct CoffeeQuery: Codable {
    let searchTerms: [String]?
}

struct SearchResults: Codable {
    let events: [Event]
    let interestGroups: [InterestGroupPublic]
    let venues: [Venue]
}

// TODO: Update this in CoffeeKit
extension InterestGroupPublic: @unchecked @retroactive Sendable { }

extension SearchResults: Content { }

struct SearchController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let searchAPI = routes.grouped("api", "v2", "search")
        searchAPI.post(use: search)
    }
    
    private func findEvents(_ searchTerms: [String]?, on db: Database) async throws -> [Event] {
        guard let searchTerms, !searchTerms.isEmpty else { return [] }
        let events = try await Event.query(on: db)
            .group(.or) { or in
                for term in searchTerms {
                    or.filter(\.$name, .custom("ILIKE"), "%\(term)%")
                }
            }
            .all()
        return events
    }
    
    private func findGroups(_ searchTerms: [String]?, on db: Database) async throws -> [InterestGroup] {
        guard let searchTerms, !searchTerms.isEmpty else { return [] }
        let groups = try await InterestGroup.query(on: db)
            .group(.or) { or in
                for term in searchTerms {
                    or.filter(\.$name, .custom("ILIKE"), "%\(term)%")
                    or.filter(\.$short, .custom("ILIKE"), "%\(term)%")
                }
            }
            .all()
        return groups
    }
    
    private func findVenues(_ searchTerms: [String]?, on db: Database) async throws -> [Venue] {
        guard let searchTerms, !searchTerms.isEmpty else { return [] }
        let venues = try await Venue.query(on: db)
            .group(.or) { or in
                for term in searchTerms {
                    or.filter(\.$name, .custom("ILIKE"), "%\(term)%")
                }
            }
            .all()
        return venues
    }
    
    private func search(req: Request) async throws -> SearchResults {
        let query = try req.query.decode(CoffeeQuery.self)
        guard let query = query.searchTerms, query.isEmpty == false else {
            return SearchResults(events: [], interestGroups: [], venues: [])
        }
        
        async let events: [Event] = findEvents(query, on: req.db)
        async let groups: [InterestGroupPublic] = findGroups(query, on: req.db).map { $0.toPublic(events: []) }
        async let venues: [Venue] = findVenues(query, on: req.db)
        
        return SearchResults(
            events: try await events,
            interestGroups: try await groups,
            venues: try await venues
        )
    }
}
