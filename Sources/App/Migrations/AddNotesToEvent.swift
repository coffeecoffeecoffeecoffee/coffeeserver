import Fluent

struct AddNotesToEvent: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .field("notes", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .deleteField("notes")
            .update()
    }
}
