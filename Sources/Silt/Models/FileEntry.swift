import Foundation
import SwiftUI

/// What a big file actually is, decided from its extension, its executable bit and,
/// when those are inconclusive, its magic number.
enum FileKind: String, CaseIterable, Identifiable, Hashable {
    case video
    case audio
    case image
    case archive
    case diskImage
    case binary
    case appPackage
    case code
    case document
    case data
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:      "Video"
        case .audio:      "Audio"
        case .image:      "Images"
        case .archive:    "Archives"
        case .diskImage:  "Disk images"
        case .binary:     "Binaries"
        case .appPackage: "Apps & bundles"
        case .code:       "Code & projects"
        case .document:   "Documents"
        case .data:       "Databases"
        case .other:      "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video:      "film.fill"
        case .audio:      "waveform"
        case .image:      "photo.fill"
        case .archive:    "doc.zipper"
        case .diskImage:  "externaldrive.fill"
        case .binary:     "terminal.fill"
        case .appPackage: "app.fill"
        case .code:       "chevron.left.forwardslash.chevron.right"
        case .document:   "doc.text.fill"
        case .data:       "cylinder.split.1x2.fill"
        case .other:      "doc.fill"
        }
    }

    /// System palette only, so every kind adapts to light and dark for free.
    var tint: Color {
        switch self {
        case .video:      Color(nsColor: .systemRed)
        case .audio:      Color(nsColor: .systemOrange)
        case .image:      Color(nsColor: .systemCyan)
        case .archive:    Color(nsColor: .systemBrown)
        case .diskImage:  Color(nsColor: .systemBlue)
        case .binary:     Color(nsColor: .systemGreen)
        case .appPackage: Color(nsColor: .systemTeal)
        case .code:       Color(nsColor: .systemMint)
        case .document:   Color(nsColor: .systemGray)
        case .data:       Color(nsColor: .systemYellow)
        case .other:      Color(nsColor: .systemGray)
        }
    }

    // MARK: - Classification

    private static let byExtension: [String: FileKind] = {
        var map: [String: FileKind] = [:]
        func add(_ kind: FileKind, _ extensions: [String]) {
            for ext in extensions { map[ext] = kind }
        }
        add(.video, ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "wmv", "flv", "prores", "braw", "r3d"])
        add(.audio, ["wav", "aiff", "aif", "mp3", "m4a", "flac", "aac", "ogg", "logicx", "band", "als", "wproj"])
        add(.image, ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif", "bmp", "raw", "cr2", "nef", "arw", "dng", "psd", "psb", "ai", "sketch", "fig", "xcf", "svg", "webp"])
        add(.archive, ["zip", "tar", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "jar", "war", "aar", "apk", "ipa", "xip", "pkg", "war"])
        add(.diskImage, ["dmg", "iso", "img", "sparsebundle", "sparseimage", "vdi", "vmdk", "qcow2", "raw", "hds", "vhdx"])
        add(.binary, ["dylib", "so", "a", "o", "wasm", "node", "exe", "bin", "class", "pyc", "beam", "rlib", "dSYM"])
        add(.code, ["xcodeproj", "xcworkspace", "playground", "swiftmodule", "framework", "xcframework"])
        add(.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "numbers", "pages", "epub", "txt", "md", "csv", "json", "xml", "log"])
        add(.data, ["db", "sqlite", "sqlite3", "realm", "mdb", "dump", "sql", "parquet", "avro", "idx", "pack"])
        add(.appPackage, ["app", "appex", "plugin", "kext", "bundle", "photoslibrary", "imovielibrary", "tvlibrary", "musiclibrary", "aplibrary", "xcarchive", "mlpackage", "mlmodel", "gguf", "safetensors"])
        return map
    }()

    /// Mach-O and universal-binary magic numbers, for files with no useful extension.
    private static let machOMagics: Set<UInt32> = [
        0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA,
    ]

    static func classify(_ url: URL, isPackage: Bool, isExecutable: Bool) -> FileKind {
        let ext = url.pathExtension.lowercased()

        if isPackage {
            return byExtension[ext] ?? .appPackage
        }
        if let known = byExtension[ext] {
            return known
        }
        if ext.isEmpty, isExecutable, looksLikeMachO(url) {
            return .binary
        }
        if isExecutable {
            return .binary
        }
        return ext.isEmpty ? .other : .other
    }

    private static func looksLikeMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return machOMagics.contains(magic.bigEndian) || machOMagics.contains(magic)
    }
}

/// One large file, or one bundle measured as a single thing.
struct FileEntry: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
    let modified: Date?
    let kind: FileKind
    let isBundle: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let full = url.deletingLastPathComponent().path
        return full.hasPrefix(home) ? "~" + full.dropFirst(home.count) : full
    }

    var modifiedLabel: String {
        guard let modified else { return "—" }
        return modified.formatted(date: .abbreviated, time: .omitted)
    }
}
