import Fluent
import FluentPostgresDriver
import JWT
import Leaf
import Vapor

#if DEBUG
    import FluentSQLiteDriver
#endif

private enum ConfigureError: Error {
    case environmentNotSet(reason: String)
}

// configures your application
public func configure(_ app: Application) throws {
    configureCORS(on: app)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    try configureDatabase(on: app)
    try databaseMigrations(on: app)

    try configureJWT(on: app)
    app.views.use(.leaf)

    try routes(app)
}

func configureCORS(on app: Application) {
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [
            .accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin,
            "File-Name"
        ]
    )
    let cors = CORSMiddleware(configuration: corsConfig)
    app.middleware.use(cors, at: .beginning)
}

func configureDatabase(on app: Application) throws {
    if app.environment.name != Environment.testing.name {
        guard let dbUsername = Environment.get("DATABASE_USERNAME"),
            let dbName = Environment.get("DATABASE_NAME")
        else {
            throw ConfigureError.environmentNotSet(reason: "Database configuration not set in environment")
        }
        let dbHostname = Environment.get("DATABASE_HOST") ?? "localhost"
        let dbPort = Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? PostgresConfiguration.ianaPortNumber
        let dbPassword = Environment.get("DATABASE_SECRET")
        let postgresConfig = PostgresConfiguration(
            hostname: dbHostname,
            port: dbPort,
            username: dbUsername,
            password: dbPassword,
            database: dbName
        )
        app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
    } else {
        #if DEBUG
            // Environment is testing. Use in-memory sqlite.
            app.databases.use(.sqlite(.memory), as: .sqlite)
        #else
            preconditionFailure("Incompatible enivornment: \(app.environment.name)")
        #endif
    }
}

func databaseMigrations(on app: Application) throws {
    app.migrations.add(CreateTodo())
    app.migrations.add(CreateInterestGroup())
    app.migrations.add(User.Migration())
    app.migrations.add(Tag.Migration())
    app.migrations.add(UserTag.Migration())
    app.migrations.add(AddSuperUser())
    app.migrations.add(CreateVenue())
    app.migrations.add(CreateEvent())
    app.migrations.add(CreateMediaContent())
    app.migrations.add(UserMediaContent.Migration())
    app.migrations.add(AddVenueMedia())
    app.migrations.add(CreateVenueMediaContent())
    app.migrations.add(PopulateInterestGroups())

    #if DEBUG
        // Always automigrate dev/test
        print("DEBUG: Automigrate Start")
        try app.autoMigrate().wait()
        print("DEBUG: Automigrate Done")
    #endif
}

func configureJWT(on app: Application) throws {
    guard let secret = Environment.get("JWT_SIGNING_SECRET") else {
        throw ConfigureError.environmentNotSet(reason: "NO JWT_SIGNING_SECRET set in envirnoment")
    }
    app.jwt.signers.use(.hs256(key: secret))
}
