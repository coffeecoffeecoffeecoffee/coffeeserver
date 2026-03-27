import Foundation

extension String {
    /// Converts a string into a URL-safe slug by lowercasing, replacing spaces with hyphens,
    /// and removing characters that are not alphanumeric or hyphens.
    func toSlug() -> String {
        let lowercased = self.lowercased()
        let alphanumericAndSpaces = lowercased.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-"
        }
        let asString = String(String.UnicodeScalarView(alphanumericAndSpaces))
        let hyphenated = asString
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return hyphenated
    }
}
