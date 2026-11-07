import Fluent
import JWT
import Vapor

extension Request {
    func isAdmin() async throws -> Bool {
        let jwtPayload = try jwt.verify(as: SessionJWTToken.self)
        guard let user = try await User.find(jwtPayload.userId, on: db) else {
            return false
        }
        return try await user.isAdmin(on: db)
    }
}

extension User {
    /// Whether this user has the `admin` tag.
    func isAdmin(on db: Database) async throws -> Bool {
        try await $tags.query(on: db)
            .filter(\.$name == "admin")
            .count() > 0
    }
}
