import Foundation
import PiAgentCore
import PiAI

#if canImport(Photos)
import Photos
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UIKit)
import UIKit
#endif

public struct MediaQueryTool: Tool, Sendable {
    public let name = "media_query"
    public let description = """
        Query the device photo library. Supports 3 actions:
        - "list": Search/filter assets by media type, date range, favorites, subtypes (screenshot, live_photo, hdr, panorama, depth, burst), \
        and location proximity. Returns a summary table with ID, Type, Subtypes, Created, Width, Height, Duration, Favorite, Location, Filename.
        - "details": Get deep metadata for a single asset by asset_id. Returns EXIF data (camera, lens, exposure, ISO, focal length), \
        GPS coordinates with reverse-geocoded address, file resources, and all asset properties.
        - "read": Get a base64-encoded JPEG thumbnail of a single asset by asset_id for vision analysis. Use max_dimension to control size.
        """

    public init() {}

    public var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "description": .string("Action to perform: 'list' to search assets, 'details' for deep metadata, 'read' for base64 thumbnail. Defaults to 'list'."),
                    "enum": .array([.string("list"), .string("details"), .string("read")]),
                ]),
                "media_type": .object([
                    "type": .string("string"),
                    "description": .string("(list) Filter by media type: 'photo', 'video', or 'all'. Defaults to 'all'."),
                    "enum": .array([.string("photo"), .string("video"), .string("all")]),
                ]),
                "favorites_only": .object([
                    "type": .string("boolean"),
                    "description": .string("(list) Only return favorited assets. Defaults to false."),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("(list) Maximum number of results to return. Defaults to 20."),
                ]),
                "sort_by": .object([
                    "type": .string("string"),
                    "description": .string("(list) Sort order: 'newest', 'oldest'. Defaults to 'newest'."),
                    "enum": .array([.string("newest"), .string("oldest")]),
                ]),
                "after_date": .object([
                    "type": .string("string"),
                    "description": .string("(list) Only return assets created after this ISO 8601 date."),
                ]),
                "before_date": .object([
                    "type": .string("string"),
                    "description": .string("(list) Only return assets created before this ISO 8601 date."),
                ]),
                "subtypes": .object([
                    "type": .string("array"),
                    "description": .string("(list) Filter by asset subtypes. OR filter — matches assets with ANY of the listed subtypes."),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("screenshot"), .string("live_photo"), .string("hdr"),
                            .string("panorama"), .string("depth"), .string("burst"),
                        ]),
                    ]),
                ]),
                "near_location": .object([
                    "type": .string("object"),
                    "description": .string("(list) Filter assets near a GPS coordinate within a radius."),
                    "properties": .object([
                        "latitude": .object([
                            "type": .string("number"),
                            "description": .string("Latitude in decimal degrees."),
                        ]),
                        "longitude": .object([
                            "type": .string("number"),
                            "description": .string("Longitude in decimal degrees."),
                        ]),
                        "radius_km": .object([
                            "type": .string("number"),
                            "description": .string("Search radius in kilometers. Defaults to 1."),
                        ]),
                    ]),
                    "required": .array([.string("latitude"), .string("longitude")]),
                ]),
                "asset_id": .object([
                    "type": .string("string"),
                    "description": .string("(details, read) The local identifier of the asset, obtained from list results."),
                ]),
                "max_dimension": .object([
                    "type": .string("integer"),
                    "description": .string("(read) Maximum pixel dimension for the thumbnail. Defaults to 512."),
                ]),
            ]),
        ])
    }

    public func execute(input: JSONValue) async throws -> AgentToolResult {
        #if canImport(Photos)
        return await executeWithPhotos(input: input)
        #else
        return AgentToolResult(output: "Error: Photos framework not available on this platform", isError: true)
        #endif
    }

    #if canImport(Photos)
    private func executeWithPhotos(input: JSONValue) async -> AgentToolResult {
        // Check authorization
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return AgentToolResult(output: "Error: Photo library access not authorized (status: \(status.rawValue))", isError: true)
        }

        let action = input["action"]?.stringValue ?? "list"

        switch action {
        case "list":
            return await executeList(input: input)
        case "details":
            return await executeDetails(input: input)
        case "read":
            return await executeRead(input: input)
        default:
            return AgentToolResult(output: "Error: Unknown action '\(action)'. Use 'list', 'details', or 'read'.", isError: true)
        }
    }

    // MARK: - List Action

    private func executeList(input: JSONValue) async -> AgentToolResult {
        let mediaType = input["media_type"]?.stringValue ?? "all"
        let favoritesOnly = input["favorites_only"]?.boolValue ?? false
        let limit = input["limit"]?.intValue ?? 20
        let sortBy = input["sort_by"]?.stringValue ?? "newest"

        let hasLocationFilter = input["near_location"] != nil
        let fetchLimit = hasLocationFilter ? limit * 5 : limit

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: sortBy == "oldest")
        ]
        fetchOptions.fetchLimit = fetchLimit

        // Build predicates
        var predicates: [NSPredicate] = []

        switch mediaType {
        case "photo":
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case "video":
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        default:
            break
        }

        if favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let afterDateStr = input["after_date"]?.stringValue,
           let afterDate = dateFormatter.date(from: afterDateStr) ?? ISO8601DateFormatter().date(from: afterDateStr) {
            predicates.append(NSPredicate(format: "creationDate > %@", afterDate as NSDate))
        }

        if let beforeDateStr = input["before_date"]?.stringValue,
           let beforeDate = dateFormatter.date(from: beforeDateStr) ?? ISO8601DateFormatter().date(from: beforeDateStr) {
            predicates.append(NSPredicate(format: "creationDate < %@", beforeDate as NSDate))
        }

        // Subtype predicates (OR filter)
        if let subtypesArray = input["subtypes"]?.arrayValue {
            let subtypeNames = subtypesArray.compactMap { $0.stringValue }
            if !subtypeNames.isEmpty {
                var subtypePredicates: [NSPredicate] = []
                for name in subtypeNames {
                    switch name {
                    case "screenshot":
                        subtypePredicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue))
                    case "live_photo":
                        subtypePredicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue))
                    case "hdr":
                        subtypePredicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoHDR.rawValue))
                    case "panorama":
                        subtypePredicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoPanorama.rawValue))
                    case "depth":
                        subtypePredicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoDepthEffect.rawValue))
                    case "burst":
                        subtypePredicates.append(NSPredicate(format: "representsBurst == YES"))
                    default:
                        break
                    }
                }
                if !subtypePredicates.isEmpty {
                    predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: subtypePredicates))
                }
            }
        }

        if !predicates.isEmpty {
            fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        let results = PHAsset.fetchAssets(with: fetchOptions)

        // Collect assets, applying location filter if needed
        var filteredAssets: [PHAsset] = []

        if hasLocationFilter {
            let lat = input["near_location"]?["latitude"]?.numberValue ?? 0
            let lon = input["near_location"]?["longitude"]?.numberValue ?? 0
            let radiusKm = input["near_location"]?["radius_km"]?.numberValue ?? 1.0
            let center = CLLocation(latitude: lat, longitude: lon)
            let radiusMeters = radiusKm * 1000.0

            results.enumerateObjects { asset, _, stop in
                guard let assetLocation = asset.location else { return }
                let distance = assetLocation.distance(from: center)
                if distance <= radiusMeters {
                    filteredAssets.append(asset)
                    if filteredAssets.count >= limit {
                        stop.pointee = true
                    }
                }
            }
        } else {
            results.enumerateObjects { asset, _, _ in
                filteredAssets.append(asset)
            }
        }

        if filteredAssets.isEmpty {
            return AgentToolResult(output: "No assets found matching the criteria")
        }

        let columns = ["ID", "Type", "Subtypes", "Created", "W", "H", "Duration", "Favorite", "Location", "Filename"]
        var rows: [[String]] = []

        for asset in filteredAssets {
            let typeStr: String
            switch asset.mediaType {
            case .image: typeStr = "photo"
            case .video: typeStr = "video"
            case .audio: typeStr = "audio"
            default: typeStr = "unknown"
            }

            let created = asset.creationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
            let duration = asset.duration > 0 ? String(format: "%.1fs", asset.duration) : "-"
            let subtypes = subtypeLabels(for: asset).joined(separator: ",")
            let location = formatLocation(asset.location)

            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename ?? "-"

            rows.append([
                asset.localIdentifier,
                typeStr,
                subtypes.isEmpty ? "-" : subtypes,
                created,
                "\(asset.pixelWidth)",
                "\(asset.pixelHeight)",
                duration,
                asset.isFavorite ? "yes" : "no",
                location,
                filename,
            ])
        }

        let header = columns.joined(separator: " | ")
        let rowsStr = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        let output = "\(header)\n\(rowsStr)\n\n\(rows.count) asset(s) found"

        return AgentToolResult(
            output: output,
            details: .table(columns: columns, rows: rows)
        )
    }

    // MARK: - Details Action

    private func executeDetails(input: JSONValue) async -> AgentToolResult {
        guard let assetId = input["asset_id"]?.stringValue, !assetId.isEmpty else {
            return AgentToolResult(output: "Error: 'asset_id' is required for the 'details' action.", isError: true)
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetchResult.firstObject else {
            return AgentToolResult(output: "Error: Asset not found for id '\(assetId)'.", isError: true)
        }

        var sections: [String] = []

        sections.append(buildBasicProperties(asset))
        sections.append(buildSubtypeSection(asset))
        sections.append(await buildLocationSection(asset))

        if asset.mediaType == .image {
            sections.append(await buildExifSection(asset))
        }

        sections.append(buildResourceSection(asset))

        let output = sections.joined(separator: "\n\n")
        return AgentToolResult(output: output)
    }

    // MARK: - Read Action

    private func executeRead(input: JSONValue) async -> AgentToolResult {
        guard let assetId = input["asset_id"]?.stringValue, !assetId.isEmpty else {
            return AgentToolResult(output: "Error: 'asset_id' is required for the 'read' action.", isError: true)
        }

        let maxDimension = input["max_dimension"]?.intValue ?? 512

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetchResult.firstObject else {
            return AgentToolResult(output: "Error: Asset not found for id '\(assetId)'.", isError: true)
        }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { result, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                continuation.resume(returning: result)
            }
        }

        guard let image, let jpegData = image.jpegData(compressionQuality: 0.8) else {
            return AgentToolResult(output: "Error: Failed to generate thumbnail for asset '\(assetId)'.", isError: true)
        }

        let base64 = jpegData.base64EncodedString()
        return AgentToolResult(
            output: "Thumbnail for asset \(assetId) (\(Int(image.size.width))x\(Int(image.size.height)))",
            details: .file(path: "photo://\(assetId)", content: "[base64:\(base64)]", language: nil)
        )
    }

    // MARK: - Helper Methods

    private func subtypeLabels(for asset: PHAsset) -> [String] {
        var labels: [String] = []
        let sub = asset.mediaSubtypes
        if sub.contains(.photoScreenshot) { labels.append("screenshot") }
        if sub.contains(.photoLive) { labels.append("live_photo") }
        if sub.contains(.photoHDR) { labels.append("hdr") }
        if sub.contains(.photoPanorama) { labels.append("panorama") }
        if sub.contains(.photoDepthEffect) { labels.append("depth") }
        if asset.representsBurst { labels.append("burst") }
        if sub.contains(.videoStreamed) { labels.append("streamed") }
        if sub.contains(.videoHighFrameRate) { labels.append("high_frame_rate") }
        if sub.contains(.videoTimelapse) { labels.append("timelapse") }
        return labels
    }

    private func formatLocation(_ location: CLLocation?) -> String {
        guard let loc = location else { return "-" }
        return String(format: "%.4f,%.4f", loc.coordinate.latitude, loc.coordinate.longitude)
    }

    private func sourceTypeLabel(_ sourceType: PHAssetSourceType) -> String {
        var labels: [String] = []
        if sourceType.contains(.typeUserLibrary) { labels.append("user_library") }
        if sourceType.contains(.typeCloudShared) { labels.append("cloud_shared") }
        if sourceType.contains(.typeiTunesSynced) { labels.append("itunes_synced") }
        return labels.isEmpty ? "unknown" : labels.joined(separator: ",")
    }

    // MARK: - Details Section Builders

    private func buildBasicProperties(_ asset: PHAsset) -> String {
        let typeStr: String
        switch asset.mediaType {
        case .image: typeStr = "photo"
        case .video: typeStr = "video"
        case .audio: typeStr = "audio"
        default: typeStr = "unknown"
        }

        let created = asset.creationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
        let modified = asset.modificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "-"
        let duration = asset.duration > 0 ? String(format: "%.1fs", asset.duration) : "-"

        return """
            == Basic Properties ==
            ID: \(asset.localIdentifier)
            Type: \(typeStr)
            Created: \(created)
            Modified: \(modified)
            Dimensions: \(asset.pixelWidth) x \(asset.pixelHeight)
            Duration: \(duration)
            Favorite: \(asset.isFavorite ? "yes" : "no")
            Hidden: \(asset.isHidden ? "yes" : "no")
            Source: \(sourceTypeLabel(asset.sourceType))
            """
    }

    private func buildSubtypeSection(_ asset: PHAsset) -> String {
        let labels = subtypeLabels(for: asset)
        let value = labels.isEmpty ? "none" : labels.joined(separator: ", ")
        return """
            == Subtypes ==
            \(value)
            """
    }

    private func buildLocationSection(_ asset: PHAsset) async -> String {
        guard let location = asset.location else {
            return """
                == Location ==
                No location data
                """
        }

        var lines: [String] = [
            "== Location ==",
            String(format: "Latitude: %.6f", location.coordinate.latitude),
            String(format: "Longitude: %.6f", location.coordinate.longitude),
            String(format: "Altitude: %.1f m", location.altitude),
        ]

        // Reverse geocode
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                var addressParts: [String] = []
                if let locality = placemark.locality { addressParts.append(locality) }
                if let adminArea = placemark.administrativeArea { addressParts.append(adminArea) }
                if let country = placemark.country { addressParts.append(country) }
                if !addressParts.isEmpty {
                    lines.append("Address: \(addressParts.joined(separator: ", "))")
                }
            }
        } catch {
            lines.append("Address: (geocoding failed)")
        }

        return lines.joined(separator: "\n")
    }

    private func buildExifSection(_ asset: PHAsset) async -> String {
        let imageData: Data? = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.version = .current

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }

        guard let imageData,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return """
                == EXIF ==
                No EXIF data available
                """
        }

        var lines: [String] = ["== EXIF =="]

        // TIFF dictionary
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake as String] { lines.append("CameraMake: \(make)") }
            if let model = tiff[kCGImagePropertyTIFFModel as String] { lines.append("CameraModel: \(model)") }
            if let software = tiff[kCGImagePropertyTIFFSoftware as String] { lines.append("Software: \(software)") }
        }

        // EXIF dictionary
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let date = exif[kCGImagePropertyExifDateTimeOriginal as String] { lines.append("DateTimeOriginal: \(date)") }
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] { lines.append("ExposureTime: \(exposure)") }
            if let fNumber = exif[kCGImagePropertyExifFNumber as String] { lines.append("FNumber: \(fNumber)") }
            if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] { lines.append("ISO: \(iso)") }
            if let focalLength = exif[kCGImagePropertyExifFocalLength as String] { lines.append("FocalLength: \(focalLength)") }
            if let focalLength35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] { lines.append("FocalLength35mm: \(focalLength35)") }
            if let lensModel = exif[kCGImagePropertyExifLensModel as String] { lines.append("LensModel: \(lensModel)") }
            if let lensMake = exif[kCGImagePropertyExifLensMake as String] { lines.append("LensMake: \(lensMake)") }
            if let bias = exif[kCGImagePropertyExifExposureBiasValue as String] { lines.append("ExposureBias: \(bias)") }
            if let metering = exif[kCGImagePropertyExifMeteringMode as String] { lines.append("MeteringMode: \(metering)") }
            if let wb = exif[kCGImagePropertyExifWhiteBalance as String] { lines.append("WhiteBalance: \(wb)") }
            if let flash = exif[kCGImagePropertyExifFlash as String] { lines.append("Flash: \(flash)") }
            if let program = exif[kCGImagePropertyExifExposureProgram as String] { lines.append("ExposureProgram: \(program)") }
            if let brightness = exif[kCGImagePropertyExifBrightnessValue as String] { lines.append("BrightnessValue: \(brightness)") }
        }

        // GPS dictionary (supplementary — altitude, speed, direction)
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let alt = gps[kCGImagePropertyGPSAltitude as String] { lines.append("GPS_Altitude: \(alt)") }
            if let speed = gps[kCGImagePropertyGPSSpeed as String] { lines.append("GPS_Speed: \(speed)") }
            if let direction = gps[kCGImagePropertyGPSImgDirection as String] { lines.append("GPS_ImgDirection: \(direction)") }
        }

        if lines.count == 1 {
            lines.append("No EXIF data available")
        }

        return lines.joined(separator: "\n")
    }

    private func buildResourceSection(_ asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if resources.isEmpty {
            return """
                == File Resources ==
                No resources
                """
        }

        var lines: [String] = ["== File Resources =="]
        for resource in resources {
            let typeLabel = resourceTypeLabel(resource.type)
            lines.append("- \(typeLabel): \(resource.originalFilename) (\(resource.uniformTypeIdentifier))")
        }
        return lines.joined(separator: "\n")
    }

    private func resourceTypeLabel(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "audio"
        case .alternatePhoto: return "alternate_photo"
        case .fullSizePhoto: return "full_size_photo"
        case .fullSizeVideo: return "full_size_video"
        case .adjustmentData: return "adjustment_data"
        case .adjustmentBasePhoto: return "adjustment_base_photo"
        case .pairedVideo: return "paired_video"
        case .fullSizePairedVideo: return "full_size_paired_video"
        case .adjustmentBasePairedVideo: return "adjustment_base_paired_video"
        case .adjustmentBaseVideo: return "adjustment_base_video"
        case .photoProxy: return "photo_proxy"
        @unknown default: return "unknown(\(type.rawValue))"
        }
    }
    #endif
}
