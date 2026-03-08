import Fluent

struct AddShortToEvent: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .field("short", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Event.schema)
            .deleteField("short")
            .update()
    }
}
