import Fluent
import Vapor

struct UserBasicAuthenticator: AsyncBasicAuthenticator {
    typealias User = App.User

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
