import CoffeeKit
import Fluent
import Vapor

func routes(_ app: Application) throws {
    let interestGroupController = InterestGroupController()
    app.get { req async throws in
        try await interestGroupController.webView(req: req)
    }
    
    let legacyGroupRoute = app.routes.grouped(":groupID")
    legacyGroupRoute.get("ical", use: interestGroupController.calendar)
    legacyGroupRoute.get(use: interestGroupController.webViewSingle)
    legacyGroupRoute.get(":eventShort", use: interestGroupController.webViewEvent)

    app.get("healthcheck") { req async -> String in
        let currentDate = Date()
        let eventCount = try? await Event.query(on: req.db).count()
        let hostName = req.url.host ?? "NOT DEFINED"
        let hostHeaderValue = req.headers.first(name: "Host") ?? "No Host header"
        let urlString = req.url.string
        let reqHeaders = req.headers.reduce("") { key, value in
            """
            \(key): \(value)
            """
        }
        
        var os = ""
        let uptimeFormatted = UptimeFormatter.formattedUptime(from: ProcessInfo.processInfo.systemUptime)
        let processorCount = String(ProcessInfo.processInfo.processorCount)
        let processorActiveCount = String(ProcessInfo.processInfo.activeProcessorCount)
        var processName = ""
        
        guard let isAdmin = try? await req.isAdmin(), isAdmin else {
            let dbHealthText = {
                switch eventCount {
                case .some(_):
                    return "DATABASE OK"
                default:
                    return "DATABASE ERROR"
                }
            }()
            return "OK: \(dbHealthText)"
        }
        
        os = ProcessInfo.processInfo.operatingSystemVersionString
        processName = String(ProcessInfo.processInfo.globallyUniqueString)
        
        
        let dbHealthText = {
            switch eventCount {
            case .some(let count):
                return "Event count = \(count)"
            default:
                return "DATABASE ERROR"
            }
        }()
        let buildDate = Date.now.formatted(.iso8601)
        return """
       OK.
       
       Build Date: \(buildDate)
       
       Request
       URL: \(urlString)
       Hostname: \(hostName)
       Host (from headers): \(hostHeaderValue)
       Headers:
       \(reqHeaders)
       
       
       Database Check: \(dbHealthText)
       
       Process: \(processName)
       
       --- 
       
       System
       Processors: \(processorCount)
       Active: \(processorActiveCount)
       
       SystemTime: \(currentDate)
       Uptime: \(uptimeFormatted)
       
       ---
       
       OS
       Version: \(os)
       """
    }
    
//    app.get("render") { req async throws -> Response in
//        req.logger.info("render start")
//        print("render a")
//        let host = req.application.http.server.configuration.hostname
//        let port = req.application.http.server.configuration.port
////        let allGetRoutes = app.routes.all.filter { route in
////            return route.method == .GET
////        }
//
//
//        for group in try await InterestGroup.query(on: req.db).all() {
//            do {
//                let groupURI = try URI(scheme: .http, host: host, port: port, path: "/groups/\(group.requireID())/events")
//                let response = try await app.client.get(groupURI)
//                guard let responseBody = response.body else {
//                    let errorMessage = "No response for \(groupURI)"
//                    req.logger.warning(.init(stringLiteral: errorMessage))
//                    throw Abort.init(.imATeapot, reason: errorMessage)
//                }
//                let filePath = try group.requireID().uuidString
//                try writeToDisk(responseBody, path: filePath)
//                req.logger.info(.init(stringLiteral: "Wrote \(group.name) to \(filePath)"))
//                print("Wrote \(group.name) to \(filePath)")
//            } catch {
//                throw Abort(.internalServerError, reason: error.localizedDescription)
//            }
//        }
//
////        for try route in allGetRoutes {
////            let routePath: String = route.path.map { pathComponent in
////                pathComponent.description
////            }
////            .reduce("") { partialResult, thisItem in
////                return partialResult + "/" + thisItem
////            }
////            let routeURI = URI(scheme: .http, host: host, port: port, path: routePath, query: nil, fragment: nil)
////            Task {
////                app.logger.info("fetching \(routePath)")
////                let response = try await app.client.get(routeURI)
////                guard let responseBody = response.body else {
////                    let errorMessage = "No response for \(routeURI)"
////                    req.logger.warning(.init(stringLiteral: errorMessage))
////                    throw Abort.init(.imATeapot, reason: errorMessage)
////                }
////                let wroteString = try writeToDisk(responseBody, path: routePath)
////                print("wrote: \(wroteString.count)")
////            }
////        }
//        req.logger.info("render end")
//        print("render x")
//        return Response(status: .ok,
//                        headers: .defaultHeaders,
//                        body: .init(stringLiteral: "OK"))
//    }
    
    func hostURL() -> String {
        #if false
        let uriProtocol = "http://"
        #else
        let uriProtocol = "webcal://"
        #endif
        let hostName = app.http.server
            .configuration.hostname
        let hostPort = app.http.server
            .configuration.port
        return uriProtocol + hostName + ":" + String(hostPort)
    }

    try app.register(collection: RenderController())
    try app.register(collection: TodoController())
    try app.register(collection: interestGroupController)
    try app.register(collection: UserController())
    try app.register(collection: TagController())
    try app.register(collection: EventController())
    try app.register(collection: VenueController())
    try app.register(collection: SearchController())
    
    let mediaDirectoryPath = app.directory.publicDirectory.appending("media")
    try app.register(collection: MediaContentController(mediaPath: mediaDirectoryPath))
}
