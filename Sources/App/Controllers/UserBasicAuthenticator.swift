import Fluent
import Vapor

struct UserBasicAuthenticator: AsyncBasicAuthenticator {
    typealias User = App.User

    func authenticate(
        basic: BasicAuthorization,
        for request: Request
    ) async throws {
        let username = basic.username.lowercased()
        let password = basic.password
        guard let user = try await User.query(on: request.db)
            .filter(\.$email == username)
            .first() else {
            request.logger.warning("USER LOGIN FAILED (WRONG EMAIL)")
            throw Abort(.forbidden)
        }
        guard try Bcrypt.verify(password, created: user.passwordHash) else {
            request.logger.warning("USER LOGIN FAILED (PASSWORD)")
            throw Abort(.forbidden)
        }
        request.auth.login(user)
   }
}
