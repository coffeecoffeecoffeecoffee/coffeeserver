import CoffeeKit
import Fluent
import Vapor

/// Web pages for signing in, signing up, and viewing your account. Register on the web route group
/// (see ``WebSession/middleware(for:)``) so requests carry the session.
struct AccountWebController: RouteCollection {
    /// Top-level paths these pages use. Group slugs share the top level (`/:groupID`), so no group may use one.
    static let reservedPaths: Set<String> = ["signin", "signup", "signout", "account"]

    func boot(routes: RoutesBuilder) throws {
        routes.get("signin", use: signInPage)
        routes.post("signin", use: signIn)
        routes.post("signup", use: signUp)
        routes.get("account", use: account)
        routes.post("signout", use: signOut)
    }

    struct SignInForm: Content {
        var email: String
        var password: String
    }

    func signInPage(req: Request) async throws -> Response {
        if req.auth.has(User.self) {
            return req.redirect(to: "/account")
        }
        return WebPage(SignInView()).response(for: req, title: "Sign In")
    }

    func signIn(req: Request) async throws -> Response {
        let form = try? req.content.decode(SignInForm.self)
        guard let form,
              let user = try await User.authenticate(email: form.email, password: form.password, on: req.db)
        else {
            req.logger.info("Web sign-in failed")
            // The same message for an unknown email and a wrong password, so it can't confirm an account exists.
            let view = SignInView(signInEmail: form?.email ?? "", signInError: "Email or password is incorrect.")
            return WebPage(view).response(for: req, status: .unauthorized, title: "Sign In")
        }
        try await WebSession.signIn(user, on: req)
        return req.redirect(to: "/account")
    }

    func signUp(req: Request) async throws -> Response {
        let create = try? req.content.decode(UserCreate.self)
        func failure(_ message: String) -> Response {
            let view = SignInView(signUpName: create?.name ?? "", signUpEmail: create?.email ?? "", signUpError: message)
            return WebPage(view).response(for: req, status: .badRequest, title: "Sign In")
        }
        do {
            try UserCreate.validate(content: req)
        } catch let error as ValidationsError {
            return failure("Please check your details: \(error.description).")
        }
        guard let create else {
            return failure("Please fill in every field.")
        }
        let user: User
        do {
            user = try await User.register(create, on: req.db)
        } catch User.RegistrationError.passwordsDoNotMatch {
            return failure("The passwords don't match.")
        } catch User.RegistrationError.emailUnavailable {
            req.logger.warning("Rejected sign-up: email address belongs to another user")
            return failure("An account with that email already exists. Sign in instead.")
        }
        req.logger.info("User created")
        try await WebSession.signIn(user, on: req)
        return req.redirect(to: "/account")
    }

    func account(req: Request) async throws -> Response {
        guard let user = req.auth.get(User.self) else {
            return req.redirect(to: "/signin")
        }
        return WebPage(AccountView(user: user)).response(for: req, title: "Your Account")
    }

    func signOut(req: Request) async throws -> Response {
        WebSession.signOut(on: req)
        return req.redirect(to: "/")
    }
}
