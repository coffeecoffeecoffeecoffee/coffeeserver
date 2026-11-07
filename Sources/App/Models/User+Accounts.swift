import CoffeeKit
import Fluent
import Vapor

/// Lets the web session store a signed-in ``User`` by ID. Fluent supplies ``User/sessionAuthenticator(_:)``.
extension User: ModelSessionAuthenticatable {}

extension User {
    enum RegistrationError: Error, Equatable {
        case passwordsDoNotMatch
        case emailUnavailable
    }

    /// Checked against when the email is unknown, so a miss takes as long as a wrong password.
    private static let unknownUserPasswordHash: String = (try? Bcrypt.hash(UUID().uuidString)) ?? ""

    /// Finds the user with `email` and checks `password`.
    /// - Returns: the user, or `nil` if the email is unknown or the password is wrong
    static func authenticate(email: String, password: String, on db: Database) async throws -> User? {
        let user = try await User.query(on: db)
            .filter(\.$email == email.lowercased())
            .first()
        let passwordHash = user?.passwordHash ?? unknownUserPasswordHash
        guard try Bcrypt.verify(password, created: passwordHash), let user else {
            return nil
        }
        return user
    }

    /// Whether no user other than `userID` has `email`.
    /// - Parameter email: an already-lowercased address, the form emails are stored and looked up in
    static func isEmailAvailable(_ email: String, excluding userID: UUID? = nil, on db: Database) async throws -> Bool {
        let query = User.query(on: db).filter(\.$email == email)
        if let userID {
            query.filter(\.$id != userID)
        }
        return try await query.first() == nil
    }

    /// Creates and saves a user from validated sign-up data. The email is stored lowercased.
    /// - Throws: ``RegistrationError`` when the passwords differ or the email is taken
    static func register(_ create: UserCreate, on db: Database) async throws -> User {
        guard create.password == create.confirmPassword else {
            throw RegistrationError.passwordsDoNotMatch
        }
        let email = create.email.lowercased()
        guard try await isEmailAvailable(email, on: db) else {
            throw RegistrationError.emailUnavailable
        }
        let user = try User(name: create.name, email: email, passwordHash: Bcrypt.hash(create.password))
        try await user.save(on: db)
        return user
    }
}
