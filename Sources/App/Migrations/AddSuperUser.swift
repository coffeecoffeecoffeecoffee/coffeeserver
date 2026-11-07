import Fluent
import Vapor

struct AddSuperUser: AsyncMigration {
    let adminName = "Server Admin"

    func prepare(on database: Database) async throws {
        try await addAdminUser(on: database)
        try await addAdminTag(on: database)
        try await addAdminTagToAdminUser(on: database)
    }
    
    func revert(on database: Database) async throws {
        guard let adminUser = try? await User.query(on: database)
            .filter(\.$name == adminName)
            .first() else {
            throw Abort(.internalServerError, reason: "Could not revert admin user")
        }
        try? await adminUser.$tags.detachAll(on: database)
        try? await Tag.query(on: database)
            .filter(\.$name == Tag.adminTagName)
            .delete()
        try? await adminUser.delete(on: database)
    }
    
    
    func addAdminUser(on database: Database) async throws {
        let maybeAdmin = try await User.query(on: database)
            .filter(\.$name == adminName)
            .first()
        guard maybeAdmin == nil else {
            print("Admin user already exists")
            return
        }
        
        guard let adminPassword = Environment.get("SERVER_ADMIN_PASSWORD"),
                let adminEmail = Environment.get("SERVER_ADMIN_EMAIL") else {
            throw Abort(.internalServerError, reason: "Could not get SERVER_ADMIN_PASSWORD from Environment")
        }
        let passwordHash = try Bcrypt.hash(adminPassword)
        let newAdmin = User(name: adminName,
                            email: adminEmail.lowercased(),
                            passwordHash: passwordHash)
        do {
            try await newAdmin.save(on: database)
            return
        } catch {
            fatalError("Could not create Server Admin user\n\(error.localizedDescription)", file: #file, line: #line)
        }
    }
    
    func addAdminTag(on database: Database) async throws {
        let maybeAdminTag = try await Tag.query(on: database)
            .filter(\.$name == Tag.adminTagName)
            .first()
        guard maybeAdminTag == nil else {
            print("Admin tag already exists")
            return
        }
        
        let newAdminTag = Tag(name: Tag.adminTagName)
        do {
            try await newAdminTag.save(on: database)
            return
        } catch {
            fatalError("Could not create Admin tag\n\(error.localizedDescription)", file: #file, line: #line)
        }
    }
    
    func addAdminTagToAdminUser(on database: Database) async throws {
        let adminTag = try await Tag.query(on: database)
            .filter(\.$name == Tag.adminTagName)
            .first()
        let admin = try await User.query(on: database)
            .filter(\.$name == adminName)
            .first()
        
        guard let adminTag,
              let admin else {
           fatalError("Admin user and Admin tag must exist before tagging Admin user with Admin tag", file: #file, line: #line)
        }
        
        do {
            try await adminTag.$users.attach(admin, on: database)
        } catch {
            fatalError("Could not create tag Admin user with Admin tag\n\(error.localizedDescription)", file: #file, line: #line)
        }
    }
}
