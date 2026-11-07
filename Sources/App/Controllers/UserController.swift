import CoffeeKit
import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let usersAPI = routes.grouped("api", "v2", "users")
        let basicProtected = usersAPI.grouped(UserBasicAuthenticator())
        let protectedUsers = usersAPI.grouped(SessionJWTToken.authenticator(), SessionJWTToken.guardMiddleware())

        usersAPI.post(use: create)

        basicProtected.post("login", use: login)

        protectedUsers.get("me", use: fetchSelf)
        protectedUsers.put("me", use: updateSelf)

        protectedUsers.get(use: index)
        protectedUsers.get(":userID", use: fetch)
        protectedUsers.put(":userID", use: updateUser)
        protectedUsers.delete(":userID", use: delete)
        protectedUsers.get(":userID", "tags", use: getTags)
    }

    func index(_ req: Request) async throws -> [UserPublic] {
        guard try await req.isAdmin() else {
            throw Abort(.unauthorized)
        }
        let users = try await User.query(on: req.db).all()
        return users.map { $0.publicValue() }
    }

    private func assertUnique(_ email: String, db: Database) async throws -> Bool {
        let maybeExistingUser = try await User.query(on: db)
            .filter(\.$email == email)
            .first()
        return maybeExistingUser == nil ? true : false
    }

    func create(_ req: Request) async throws -> Response {
        try UserCreate.validate(content: req)
        let create = try req.content.decode(UserCreate.self)
        guard create.password == create.confirmPassword else {
            throw Abort(.badRequest, reason: "Passwords did not match")
        }
        guard let isUnique = try? await assertUnique(create.email, db: req.db),
            isUnique
        else {
            req.logger.warning("A user with this email address exists: \(create.email)")
            throw Abort(.badRequest)
        }
        let user = try User(
            name: create.name,
            email: create.email.lowercased(),
            passwordHash: Bcrypt.hash(create.password)
        )
        try await user.save(on: req.db)
        req.logger.info("User created")
        return try await user.publicValue().encodeResponse(
            status: .created,
            headers: ["Content-Type": "application/json"],
            for: req
        )
    }

    func fetch(_ req: Request) async throws -> UserPublic {
        guard let user = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return user.publicValue()
    }

    func fetchSelf(_ req: Request) async throws -> UserPrivate {
        let payload = try req.jwt.verify(as: SessionJWTToken.self)
        guard let user = try await User.find(payload.userId, on: req.db) else {
            throw Abort(.badRequest)
        }
        return user.privateValue()
    }

    func delete(_ req: Request) async throws -> HTTPStatus {
        let payload = try req.jwt.verify(as: SessionJWTToken.self)
        guard let requestingUser = try await User.find(payload.userId, on: req.db) else {
            req.logger.info("Unauthorized user delete attempt\n\(req)")
            throw Abort(.unauthorized)
        }
        guard let userIdString = req.parameters.get("userID"),
            let userIdToDelete = UUID(userIdString),
            let user = try await User.find(userIdToDelete, on: req.db)
        else {
            throw Abort(.badRequest, reason: "Cannot find userID")
        }
        let isSelfDelete = try requestingUser.requireID() == userIdToDelete
        let canDelete = try await isSelfDelete ? true : req.isAdmin()
        guard canDelete else {
            req.logger.info("Unauthorized attempt to delete user\n\(req)")
            return .unauthorized
        }
        // Deleting an admin is deliberately not possible through the API, including an admin
        // deleting themselves. Remove the admin tag directly in the database first.
        let targetIsAdmin = try await user.isAdmin(on: req.db)
        guard !targetIsAdmin else {
            req.logger.warning("Refused to delete admin user \(userIdString)")
            throw Abort(.forbidden, reason: "Admin users cannot be deleted")
        }
        // Uploads outlive their owner: an admin delete hands them to that admin, and a
        // self-delete hands them to the server admin.
        let mediaRecipient = isSelfDelete ? try await serverAdmin(on: req.db) : requestingUser
        try await deleteUser(user, handingMediaTo: mediaRecipient, on: req.db)
        req.logger.info(isSelfDelete
            ? "User requests to self-delete. UserID \(userIdString)"
            : "Admin delete of user \(userIdString)")
        return .noContent
    }

    /// Hands the user's uploads to `recipient`, removes their tag links, then deletes the user, all or nothing.
    /// - Throws: `Abort(.conflict)` if the user has uploads and `recipient` is `nil`
    private func deleteUser(_ user: User, handingMediaTo recipient: User?, on db: Database) async throws {
        let userID = try user.requireID()
        let recipientID = try recipient?.requireID()
        try await db.transaction { transaction in
            let ownedMedia = MediaContent.query(on: transaction).filter(\.$user.$id == userID)
            let mediaLinks = UserMediaContent.query(on: transaction).filter(\.$user.$id == userID)
            if let recipientID {
                try await ownedMedia.set(\.$user.$id, to: recipientID).update()
                try await mediaLinks.set(\.$user.$id, to: recipientID).update()
            } else {
                guard try await ownedMedia.count() == 0 else {
                    throw Abort(.conflict, reason: "User has uploaded media and there is no admin to hand it to")
                }
                try await mediaLinks.delete()
            }
            try await user.$tags.detachAll(on: transaction)
            try await user.delete(on: transaction)
        }
    }

    /// The account created by ``AddSuperUser``, or any admin if that account has been renamed.
    private func serverAdmin(on db: Database) async throws -> User? {
        if let named = try await User.query(on: db).filter(\.$name == AddSuperUser().adminName).first(),
           try await named.isAdmin(on: db) {
            return named
        }
        return try await User.query(on: db)
            .join(siblings: \.$tags)
            .filter(Tag.self, \.$name == "admin")
            .first()
    }
}

// MARK: - Update User
extension UserController {
    private func parseAndSave(_ user: User, req: Request) async throws -> UserPrivate {
        do {
            try UserCreate.validate(content: req)
        } catch {
            req.logger.info("User Validation failed: \(String(describing: error))")
            throw Abort(.badRequest, reason: "Invalid user data: \(String(describing: error))")
        }
        let newUpdates = try req.content.decode(UserCreate.self)
        guard newUpdates.password == newUpdates.confirmPassword else {
            throw Abort(.badRequest, reason: "Passwords did not match")
        }
        if user.$email.wrappedValue != newUpdates.email {
            guard let isUnique = try? await assertUnique(newUpdates.email, db: req.db),
                isUnique
            else {
                req.logger.warning("A user with this email address exists: \(newUpdates.email)")
                throw Abort(.badRequest)
            }
        }
        user.name = newUpdates.name
        user.email = newUpdates.email
        user.passwordHash = try Bcrypt.hash(newUpdates.password)
        try await user.update(on: req.db)
        return user.privateValue()
    }

    /// Admin authorized user updating
    /// - Parameter req: Admin-authorized `Request` containing ``User.Create`` payload
    /// - Returns: ``User.Private``
    func updateUser(_ req: Request) async throws -> UserPrivate {
        guard try await req.isAdmin() else {
            req.logger.warning("Unauthorized attempt to update as admin")
            throw Abort(.unauthorized)
        }
        guard let newUser = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return try await parseAndSave(newUser, req: req)
    }

    /// Self-service ``User`` updating.
    /// Only the signed-in ``User`` can authorize their own updated values on this route. Admins should use the ``updateUser(_ req:)``
    /// method to update another ``User``.
    /// - Parameter req: ``User`` with valid session and ``User.Create`` payload
    /// - Returns: ``User.Private``
    func updateSelf(_ req: Request) async throws -> UserPrivate {
        let payload = try req.jwt.verify(as: SessionJWTToken.self)
        guard let user = try await User.find(payload.userId, on: req.db) else {
            req.logger.warning("Attempt to update non-existent user")
            throw Abort(.notFound, reason: "Could not find user")
        }
        return try await parseAndSave(user, req: req)
    }
}

// MARK: - Auth
extension UserController {
    func login(_ req: Request) async throws -> Response {
        do {
            let user = try req.auth.require(User.self)
            let tags = try await user.$tags.get(on: req.db)
            let token = try SessionJWTToken(user: user, tags: tags)
            let signedToken = try req.jwt.sign(token)

            req.logger.info("User login: \(user.id?.uuidString ?? "no id")")

            return try await [
                "error": "false",
                "message": "logged in as \(user.name)",
                "jwt-token": signedToken,
            ].encodeResponse(status: .ok, for: req)
        } catch {
            req.logger
                .warning(
                    "Login failure: method=\(req.method.rawValue) path=\(req.url.path) remoteAddress=\(req.remoteAddress?.description ?? "unknown")"
                )
            return try await [
                "error": "true",
                "message": error.localizedDescription,
            ].encodeResponse(status: .unauthorized, for: req)
        }
    }
}

// MARK: - Tags
extension UserController {
    func getTags(_ req: Request) async throws -> [Tag] {
        guard try await req.isAdmin() else {
            throw Abort(.unauthorized)
        }
        guard let user = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return try await user.$tags.get(on: req.db)
    }
}
