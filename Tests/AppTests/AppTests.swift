@testable import App
import VaporTesting
import Testing

@Suite("App Tests")
struct AppTests {
    @Test("Healthcheck")
    func healthcheck() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "healthcheck") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("OK"))
            }
        }
    }
    
    @Test("Admin healthcheck lists headers but redacts credentials")
    func adminHealthcheckRedactsCredentials() async throws {
        try await withApp(configure: configure) { app in
            let adminJWT = try await loginAsAdmin(app: app)
            let cookie = "session=cookie-secret-value"
            try await app.testing().test(
                .GET, "healthcheck",
                headers: [
                    "Authorization": "Bearer \(adminJWT)",
                    "Cookie": cookie,
                    "X-Forwarded-Host": "coffee.example.com",
                ]
            ) { res async in
                #expect(res.status == .ok)
                let body = res.body.string
                #expect(body.contains("Event count"), "Admin gets the full diagnostics page")
                #expect(!body.contains(adminJWT), "Session JWT is not echoed back")
                #expect(!body.contains(cookie), "Cookie is not echoed back")
                #expect(body.localizedCaseInsensitiveContains("Authorization: <redacted>"))
                #expect(body.localizedCaseInsensitiveContains("Cookie: <redacted>"))
                #expect(body.contains("X-Forwarded-Host: coffee.example.com"), "Other headers are still listed")
            }
        }
    }

    @Test("Homepage")
    func homepage() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "") { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Coffee Coffee Coffee Coffee"))
            }
        }
    }
}
