import Foundation

enum LeftoverConfidence: String, Sendable {
    case high = "HIGH", low = "LOW"

    /// Shown to people, unlike `rawValue`, which rendered as a shouted "HIGH"/"LOW".
    var label: String { self == .high ? "Confident match" : "Possible match" }
}

struct AppLeftoverItem: Identifiable, Sendable {
    let url: URL
    let matchedID: String
    let location: String
    let bytes: Int64
    let confidence: LeftoverConfidence
    var id: String { url.path }
}

struct AppLeftoverGroup: Identifiable, Sendable {
    let id: String
    let name: String
    let confidence: LeftoverConfidence
    let items: [AppLeftoverItem]
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var isDeletable: Bool { confidence == .high }
}
