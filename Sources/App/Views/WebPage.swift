import Plot
import Vapor

struct WebPage {
    private let content: Component
    
    init(_ content: Component) {
        self.content = Node.body { content }
    }
    
    /// Renders the page for `req`, with the account link for whoever is signed in.
    public func response(
        for req: Request,
        status: HTTPResponseStatus = .ok,
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
            .body { buildBody(user: req.auth.get(User.self)) }
        ).render()
        let resposneHeaders: HTTPHeaders = HTTPHeaders(dictionaryLiteral:
            ("Content-Type", "text/html"),
            ("ETag", "bean_\(body.hashValue)"),
            // Pages show who is signed in, so shared caches must not reuse them across visitors.
            ("Cache-Control", "private, no-cache"),
            ("Vary", "Cookie")
        )
        return Response(status: status, headers: resposneHeaders, body: .init(string: body))
    }
    
    
    private func buildBody(user: User?) -> Component {
        Div {
            AccountNav(user: user)
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

/// Top-of-page link to the visitor's account, or to sign in.
struct AccountNav: Component {
    let user: User?

    var body: Component {
        Navigation {
            if let user {
                Link(user.name, url: "/account")
                    .class("white-button")
            } else {
                Link("Sign In", url: "/signin")
                    .class("white-button")
            }
        }
        .class("account-nav")
    }
}

extension String {
    /// Escapes text for a double-quoted HTML attribute. Plot escapes text nodes but writes attribute
    /// values verbatim, so anything user-supplied that goes into an attribute must pass through this.
    var htmlAttributeEscaped: String {
        var escaped = ""
        for character in self {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
