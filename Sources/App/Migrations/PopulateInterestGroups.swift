import Fluent

struct PopulateInterestGroups: AsyncMigration {
    let groupData = [
        InterestGroup(
            id: UUID("28ef50f9-b909-4f03-9a69-a8218a8cbd99")!,
            name: "SF iOS Coffee",
            short: "sf-ios-coffee",
            isArchived: false
        ),
        InterestGroup(
            id: UUID("43d31984-7322-4965-bc9c-25abb335536b")!,
            name: "SF Rails Coffee",
            short: "sf-rails-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("863f78cf-bb02-4673-aba8-153fa2d331be"),
            name: "Rochester",
            short: "rochester",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("a9bb1bb9-536f-4093-8311-d18a9251384c"),
            name: "Product Of SFO",
            short: "product-of-sfo",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("5b1fadd6-ad57-4607-930a-f72ab252db5c"),
            name: "SF iOS Beer",
            short: "sf-ios-beer",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("4489a290-53a2-45b5-9272-d074a9e8b0c1"),
            name: "Austin iOS Coffee",
            short: "austin-ios-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("f95793f2-5c1d-4fdd-b9c0-f5497dd445e0"),
            name: "WWDC Coffee",
            short: "wwdc",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("1fe6288a-9102-48ac-9043-a03c959f5adb"),
            name: "MSP Coffee",
            short: "msp-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("d9fc6db5-097f-4c6d-bebd-b738c000f4e1"),
            name: "Seattle iOS Coffee",
            short: "seattle-ios-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("8a298968-cb2f-4288-8183-c79cdbd643a2"),
            name: "NYC iOS Coffee",
            short: "nyc-ios-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("b2142354-b7c6-42fd-8b1f-914c4a7c1d9b"),
            name: "Chicagoland iOS Coffee",
            short: "chicagoland-ios-coffee",
            imageURL: nil,
            isArchived: true
        ),
        InterestGroup(
            id: UUID("ff2cc96d-ac23-4df3-83cf-0524f76391b2"),
            name: "San Diego Coffee",
            short: "san-diego-coffee",
            imageURL: nil,
            isArchived: false
        ),
        InterestGroup(
            id: UUID("55fd184a-1a54-49f4-ba84-cf5f25c73ee2"),
            name: "South Bay iOS Coffee",
            short: "south-bay-ios-bubble-tea",
            imageURL: nil,
            isArchived: false
        ),
    ]

    func prepare(on database: any Database) async throws {
        for oldGroup in groupData {
            try await oldGroup.save(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        for oldGroup in groupData {
            try await InterestGroup.find(oldGroup.id, on: database)?.delete(on: database)
        }
    }
}
