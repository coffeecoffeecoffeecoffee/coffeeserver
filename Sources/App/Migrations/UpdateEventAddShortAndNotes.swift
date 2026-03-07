import Fluent

struct UpdateEventAddShortAndNotes: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .field("short", .string)
            .field("notes", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .deleteField("short")
            .deleteField("notes")
            .update()
    }
}
