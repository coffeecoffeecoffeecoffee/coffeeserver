import Plot
import Vapor

struct WebPage {
    private let content: Component
    
    init(_ content: Component) {
        self.content = Node.body { content }
    }
    
    public func response(
        status: HTTPResponseStatus = .ok,
        headers: HTTPHeaders = .defaultHeaders,
        title: String = "Coffee",
        ogPath: String? = nil,
        ogImagePath: String? = nil
    ) -> Response {
        let body = HTML(
            .head(
                .encoding(.utf8),
                .title(title),
                .meta(
                    .name("viewport"),
                    .content("width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0")
                ),
                .meta(
                    .property("og:site_name"),
                    .content("Coffee Coffee Coffee Coffee")
                ),
                .meta(
                    .property("og:title"),
                    .content(title)
                ),
                .meta(
                    .property("og:url"),
                    .content(ogPath ?? "https://coffeecoffeecoffee.coffee"),
                ),
                .meta(
                    .property("og:image"),
                    .content(ogImagePath ?? "https://coffeecoffeecoffee.coffee/default-coffee.webp")
                ),
                .stylesheet("/style.css"),
            ),
            .body(buildBody)
        ).render()
        let resposneHeaders: HTTPHeaders = HTTPHeaders(dictionaryLiteral:
            ("Content-Type", "text/html"),
            ("ETag", "bean_\(body.hashValue)")
        )
        return Response(status: status, headers: resposneHeaders, body: .init(string: body))
    }
    
    
    private func buildBody() -> Component {
        Div {
            self.content
            Footer {
                Link("Email Support", url: "mailto:coffee@pixel.science")
                    .class("white-button")
                Link("Code of Conduct", url: "https://github.com/coffeecoffeecoffeecoffee/Coffee-Code-Of-Conduct")
                    .class("white-button")
            }
        }
        .class("wrapper")
    }
}
