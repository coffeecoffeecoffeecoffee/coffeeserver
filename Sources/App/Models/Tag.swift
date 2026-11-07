import Fluent
import Vapor

final class Tag: Model, Content, @unchecked Sendable {
    static let schema = "tags"

    /// Name of the tag that grants admin privileges
    static let adminTagName = "admin"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String
    
    @Siblings(through: UserTag.self, from: \.$tag, to: \.$user)
    public var users: [User]
    
    init() { }

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

extension Tag: Validatable {
    static func validations(_ validations: inout Vapor.Validations) {
        validations.add("name", as: String.self, is: !.empty)
    }
}
