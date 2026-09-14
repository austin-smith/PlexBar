import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum StudioFiles {
    /// The checkout used to build this developer tool is its only content source.
    private static var repositoryURL: URL {
        get throws {
            guard let path = Bundle.main.object(forInfoDictionaryKey: "StudioRepositoryPath") as? String,
                  !path.isEmpty else {
                throw StudioError.invalid("Studio’s repository path is missing. Rebuild the PlexBarStudio scheme from this checkout.")
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    static var repositoryContentURL: URL {
        get throws { try repositoryURL.appending(path: "PlexBar/Resources/MockServer", directoryHint: .isDirectory) }
    }

    static var artworkInstructionsURL: URL {
        get throws { try resolved("Studio/artwork-instructions.json", in: repositoryURL) }
    }

    static func historyURL(in content: URL) throws -> URL {
        try resolved(".studio", in: content)
    }

    static func resolved(_ relativePath: String, in root: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw StudioError.invalid("Invalid relative resource path: \(relativePath)")
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        var componentURL = base
        for component in relativePath.split(separator: "/") {
            componentURL.append(path: String(component))
            // Foundation does not resolve an intermediate symlink when the final file is absent.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                throw StudioError.invalid("Symbolic links are not supported in resource paths: \(relativePath)")
            }
        }
        let result = base.appending(path: relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard result.path.hasPrefix(base.path + "/") else { throw StudioError.invalid("Resource is outside its content folder: \(relativePath)") }
        return result
    }

    static func loadPack(at root: URL) throws -> StudioPack {
        let decoder = JSONDecoder()
        return try StudioPack(
            records: decoder.decode([StudioCatalogRecord].self, from: Data(contentsOf: root.appending(path: "media-catalog.json"))),
            payload: decoder.decode(StudioJSON.self, from: Data(contentsOf: root.appending(path: "mock-server.json")))
        )
    }

    static func savePack(_ pack: StudioPack, at root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(pack.records).write(to: root.appending(path: "media-catalog.json"), options: .atomic)
        try pack.payload.encoded().write(to: root.appending(path: "mock-server.json"), options: .atomic)
    }

    static func loadManifest(at root: URL) throws -> StudioManifest {
        let manifest = try JSONDecoder().decode(StudioManifest.self, from: Data(contentsOf: root.appending(path: "studio.json")))
        guard manifest.schemaVersion == 2 else { throw StudioError.invalid("This generation history uses an unsupported format version.") }
        return manifest
    }

    static func saveManifest(_ manifest: StudioManifest, at root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: root.appending(path: "studio.json"), options: .atomic)
    }

    /// Publish reviewed content and its decision together, preserving all other resource files.
    @discardableResult
    static func commitContent(_ pack: StudioPack, manifest: StudioManifest, at root: URL,
                              expected: [String: String], files: [String: Data] = [:]) throws -> [String: String] {
        guard try fingerprints(at: root) == expected else {
            throw StudioError.invalid("PlexBar’s mock content changed outside Studio. Reload Content before saving this edit or accepting the draft.")
        }
        let staging = root.deletingLastPathComponent().appending(path: ".studio-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where child.lastPathComponent != ".studio" {
            try FileManager.default.copyItem(at: child, to: staging.appending(path: child.lastPathComponent))
        }
        for (path, data) in files {
            guard !path.hasPrefix(".studio/") else { throw StudioError.invalid("Artwork cannot overwrite generation history.") }
            let target = try resolved(path, in: staging)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        try savePack(pack, at: staging)
        try saveManifest(manifest, at: historyURL(in: staging))
        let issues = pack.validate() + validateAssets(pack, at: staging)
        guard issues.isEmpty else { throw StudioError.invalid(issues.map(\.message).joined(separator: "\n")) }
        let savedFingerprint = try fingerprints(at: staging)
        guard try fingerprints(at: root) == expected else {
            throw StudioError.invalid("PlexBar’s mock content changed while saving. Nothing was saved. Reload Content and review again.")
        }
        var writes = files
        for path in ["media-catalog.json", "mock-server.json", ".studio/studio.json"] {
            writes[path] = try Data(contentsOf: resolved(path, in: staging))
        }
        try StudioContentTransaction.write(writes, at: root)
        return savedFingerprint
    }

    /// Drafts and job results never write the accepted catalog or artwork.
    static func saveHistory(_ manifest: StudioManifest, at root: URL, files: [String: Data] = [:]) throws {
        // Publish result files before the manifest references them. Other jobs may
        // still have open file handles anywhere beneath this directory.
        for (path, data) in files {
            let target = try resolved(path, in: root)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
        try saveManifest(manifest, at: root)
    }

    static func fingerprints(at root: URL) throws -> [String: String] {
        guard let entries = FileManager.default.enumerator(atPath: root.path) else {
            throw StudioError.invalid("Cannot read the mock resource folder.")
        }
        var result: [String: String] = [:]
        for case let relative as String in entries {
            if relative == ".studio" {
                entries.skipDescendants()
                continue
            }
            let url = root.appending(path: relative)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw StudioError.invalid("Symbolic links are not supported in mock packs: \(relative)") }
            if values.isRegularFile == true {
                // Relative enumeration avoids mixing /var and /private/var aliases.
                result[relative] = hash(try Data(contentsOf: url))
            }
        }
        return result
    }

    static func validateAssets(_ pack: StudioPack, at root: URL) -> [StudioValidationIssue] {
        pack.assets.compactMap { asset in
            do {
                let url = try resolved(asset.resource, in: root)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw StudioError.invalid("Artwork could not be decoded.")
                }
                return nil
            } catch { return StudioValidationIssue(context: asset.resource, message: error.localizedDescription) }
        }
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func normalizedReference(at url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw StudioError.invalid("The reference image cannot be decoded.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw StudioError.invalid("Cannot prepare the reference image.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StudioError.invalid("Cannot prepare the reference image.") }
        return data as Data
    }

    static func exportImage(_ data: Data, role: StudioArtworkRole) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw StudioError.invalid("The generated image cannot be decoded.") }
        let ratio = Double(image.width) / Double(image.height)
        guard abs(ratio - role.ratio) < 0.015 else {
            throw StudioError.invalid("This image is \(image.width) × \(image.height). Generate or import the \(role.title.lowercased()) in the correct aspect ratio before accepting it.")
        }
        let size = role.exportSize
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StudioError.invalid("Unable to create the artwork export context.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let output = context.makeImage() else { throw StudioError.invalid("Unable to render artwork.") }
        let data = NSMutableData()
        let type = role == .backdrop ? UTType.jpeg.identifier : UTType.png.identifier
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { throw StudioError.invalid("Unable to encode artwork.") }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StudioError.invalid("Unable to finish artwork export.") }
        return data as Data
    }
}
