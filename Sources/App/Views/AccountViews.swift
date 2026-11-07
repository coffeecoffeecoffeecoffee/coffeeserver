import Plot

/// The logo header shared by the account pages, matching the group pages.
private struct AccountPageHeader: Component {
    let title: String

    var body: Component {
        Header {
            Link(url: "/") {
                Image(url: "/logo-long.png", description: "Home")
                    .class("header-image")
            }
            H1(title)
        }
    }
}

/// A labeled form field. `value` is user-supplied, so it is attribute-escaped.
private struct FormField: Component {
    let label: String
    let type: HTMLInputType
    let name: String
    var value: String = ""
    let autocomplete: String

    var body: Component {
        Label(label) {
            Input(type: type, name: name, value: value.htmlAttributeEscaped, isRequired: true)
                .attribute(named: "autocomplete", value: autocomplete)
        }
    }
}

private struct FormError: Component {
    let message: String?

    var body: Component {
        guard let message else {
            return EmptyComponent()
        }
        return Paragraph(message)
            .class("form-error")
            .attribute(named: "role", value: "alert")
    }
}

/// Sign-in and sign-up on one page. Field values are only ever the visitor's own input,
/// and passwords are never filled back in.
struct SignInView: Component {
    var signInEmail = ""
    var signInError: String?
    var signUpName = ""
    var signUpEmail = ""
    var signUpError: String?

    var body: Component {
        Div {
            AccountPageHeader(title: "Sign In")
            Div {
                Div {
                    H2("Sign in")
                    FormError(message: signInError)
                    Form(url: "/signin", method: .post) {
                        // "webauthn" lets passkey autofill attach to this field once passkeys ship.
                        FormField(label: "Email", type: .email, name: "email",
                                  value: signInEmail, autocomplete: "username webauthn")
                        FormField(label: "Password", type: .password, name: "password",
                                  autocomplete: "current-password")
                        SubmitButton("Sign In")
                    }
                }
                .class("account-card")
                .id("sign-in")

                Div {
                    H2("Create an account")
                    FormError(message: signUpError)
                    Form(url: "/signup", method: .post) {
                        FormField(label: "Name", type: .text, name: "name",
                                  value: signUpName, autocomplete: "name")
                        FormField(label: "Email", type: .email, name: "email",
                                  value: signUpEmail, autocomplete: "email")
                        FormField(label: "Password (at least 8 characters)", type: .password, name: "password",
                                  autocomplete: "new-password")
                        FormField(label: "Confirm password", type: .password, name: "confirmPassword",
                                  autocomplete: "new-password")
                        SubmitButton("Create Account")
                    }
                }
                .class("account-card")
                .id("sign-up")
            }
            .class("account-cards")
        }
    }
}

/// The signed-in user's own details.
struct AccountView: Component {
    let user: User

    var body: Component {
        Div {
            AccountPageHeader(title: "Your Account")
            Div {
                Div {
                    H2(user.name)
                    Paragraph(user.email)
                        .class("account-email")
                    Form(url: "/signout", method: .post) {
                        SubmitButton("Sign Out")
                    }
                }
                .class("account-card")
            }
            .class("account-cards")
        }
    }
}
