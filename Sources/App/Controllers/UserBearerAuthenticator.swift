import Fluent
import Vapor

struct UserBearerAuthenticator: AsyncBearerAuthenticator {
    typealias User = App.User

    func authenticate(
        bearer: Vapor.BearerAuthorization,
        for request: Vapor.Request
    ) async throws {
        
    }
    

    func authenticate(
        basic: BasicAuthorization,
        for request: Request
    ) async throws {
        guard let user = try await User.authenticate(
            email: basic.username,
            password: basic.password,
            on: request.db
        ) else {
            request.logger.warning("USER LOGIN FAILED")
            throw Abort(.forbidden)
        }
        request.auth.login(user)
   }
}
