import Foundation

// Emits docs/catalog.md from the live catalog, so the reference can never drift
// from the code. Regenerate with:
//   swiftc -O -o /tmp/dumpcat Sources/Silt/Models/CleanTarget.swift \
//     Sources/Silt/Models/Catalog.swift docs/tools/dump-catalog/main.swift
//   /tmp/dumpcat > docs/catalog.md

let home = FileManager.default.homeDirectoryForCurrentUser.path
func tilde(_ url: URL) -> String {
    let p = url.path
    return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}
func kindLabel(_ k: CleanKind) -> String {
    switch k {
    case .safe: "Safe"
    case .prunable: "Re-downloads"
    case .review: "Review-only"
    }
}

print("# Catalog reference")
print("")
print("> Generated from `Sources/Silt/Models/Catalog.swift` — do not edit by hand.")
print("> Regenerate: `swiftc -O -o /tmp/dumpcat Sources/Silt/Models/CleanTarget.swift Sources/Silt/Models/Catalog.swift docs/tools/dump-catalog/main.swift && /tmp/dumpcat > docs/catalog.md`")
print("")
print("\(Catalog.all.count) locations. **Safe** = regenerates silently. **Re-downloads** = comes back at the cost of a download or rebuild. **Review-only** = Silt will never delete it; the consequence column carries the correct command instead.")

for category in CleanCategory.allCases {
    let inCategory = Catalog.all.filter { $0.category == category }
    guard !inCategory.isEmpty else { continue }
    print("\n## \(category.title) — \(inCategory.count) locations\n")
    var seenGroups: [String] = []
    for t in inCategory where !seenGroups.contains(t.group) { seenGroups.append(t.group) }
    for group in seenGroups {
        let rows = inCategory.filter { $0.group == group }
        if seenGroups.count > 1 { print("### \(group)\n") }
        print("| Location | Owner | Path | Kind | What happens if it goes |")
        print("|---|---|---|---|---|")
        for t in rows {
            let path = tilde(t.path).replacingOccurrences(of: "|", with: "\\|")
            let why = t.consequence.replacingOccurrences(of: "|", with: "\\|")
            print("| \(t.name) | \(t.owner) | `\(path)` | \(kindLabel(t.kind)) | \(why) |")
        }
        print("")
    }
}
