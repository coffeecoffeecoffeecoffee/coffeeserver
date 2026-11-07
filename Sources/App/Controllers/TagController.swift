import Fluent
import Vapor

final class TagController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let tagsAPI = routes.grouped("api", "v2", "tags")
            .grouped(SessionJWTToken.authenticator(), SessionJWTToken.guardMiddleware())
        tagsAPI.get(use: index)
        tagsAPI.post(use: create)
        tagsAPI.group(":tagID") { tag in
            tag.get(use: fetch)
            tag.delete(use: delete)
        }
        tagsAPI.post(":tagID", "attach", ":userID", use: attachUser)
    }
    
    func index(req: Request) async throws -> [Tag] {
        try await Tag.query(on: req.db).all()
    }
    
    func create(req: Request) async throws -> Tag {
        let tag = try req.content.decode(Tag.self)
        try await tag.save(on: req.db)
        return tag
    }
    
    func fetch(req: Request) async throws -> Tag {
        guard let tag = try await Tag.find(req.parameters.get("tagID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return tag
    }
    
    func delete(req: Request) async throws -> HTTPStatus {
        guard let tag = try await Tag.find(req.parameters.get("tagID"), on: req.db) else {
            throw Abort(.notFound)
        }
        guard tag.name != Tag.adminTagName else {
            throw Abort(.unauthorized, reason: "Admin tag must not be deleted")
        }
        try await tag.delete(on: req.db)
        return .noContent
    }
    
    func attachUser(req: Request) async throws -> HTTPStatus {
        guard try await req.isAdmin() else {
            throw Abort(.unauthorized)
        }
        guard let tagString = req.parameters.get("tagID"),
              let tagID = UUID(uuidString: tagString),
              let userString = req.parameters.get("userID"),
              let userID = UUID(uuidString: userString) else {
            throw Abort(.badRequest)
        }
        async let user = User.find(userID, on: req.db)
        async let tag = Tag.find(tagID, on: req.db)
        guard try await tag != nil,
              try await user != nil else {
            throw Abort(.notFound)
        }
        try await user!.$tags.attach(tag!, on: req.db)
        return .created
    }
}
