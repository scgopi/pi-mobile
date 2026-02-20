import Foundation

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

// MARK: - Data Types

public struct PickedFileInfo: Sendable {
    public let bookmarkId: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int?
    public let contentType: String?
    public let modificationDate: Date?
    public let creationDate: Date?
}

public struct DirectoryEntry: Sendable {
    public let name: String
    public let isDirectory: Bool
    public let size: Int?
    public let contentType: String?
    public let modificationDate: Date?
}

public struct GrantInfo: Sendable {
    public let id: String
    public let name: String?
    public let isValid: Bool
}

// MARK: - FileAccessManager

@MainActor
public final class FileAccessManager: NSObject {
    public static let shared = FileAccessManager()

    private weak var presentingViewController: UIViewController?
    private var bookmarks: [String: Data] = [:]
    private let storageKey = "com.pi.fileAccessBookmarks"
    private var activeCoordinator: PickerCoordinator?

    private override init() {
        super.init()
        loadBookmarks()
    }

    /// Optionally set an explicit presenting view controller. If not set, the manager
    /// auto-discovers the topmost view controller from the active window scene.
    public func configure(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
    }

    /// Returns the topmost view controller for presenting the document picker.
    /// Prefers an explicitly configured VC, otherwise walks the active window scene.
    private var topViewController: UIViewController? {
        if let vc = presentingViewController { return vc }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let window = scene.windows.first(where: { $0.isKeyWindow }),
            var topVC = window.rootViewController
        else { return nil }

        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    // MARK: - Bookmark Persistence

    private func loadBookmarks() {
        if let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Data] {
            bookmarks = stored
        }
    }

    private func persistBookmarks() {
        UserDefaults.standard.set(bookmarks, forKey: storageKey)
    }

    private func storeBookmark(for url: URL) -> String? {
        // Use default options (not .minimalBookmark) to preserve security scope on iOS
        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        let id = UUID().uuidString
        bookmarks[id] = data
        persistBookmarks()
        return id
    }

    /// Resolve a bookmark ID to a URL. Refreshes stale bookmarks automatically.
    public func resolveBookmark(_ id: String) -> URL? {
        guard let data = bookmarks[id] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let refreshed = try? url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    bookmarks[id] = refreshed
                    persistBookmarks()
                }
            }
        }
        return url
    }

    // MARK: - File Picker

    public func pickFiles(contentTypes: [UTType], allowsMultiple: Bool) async -> [PickedFileInfo]? {
        guard let vc = topViewController else { return nil }

        let urls: [URL]? = await withCheckedContinuation { continuation in
            let coordinator = PickerCoordinator(pickContinuation: continuation)
            self.activeCoordinator = coordinator

            let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
            picker.allowsMultipleSelection = allowsMultiple
            picker.delegate = coordinator
            vc.present(picker, animated: true)
        }
        self.activeCoordinator = nil

        guard let urls, !urls.isEmpty else { return nil }

        var results: [PickedFileInfo] = []
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let bookmarkId = storeBookmark(for: url) else { continue }

            let rv = try? url.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                .contentTypeKey, .isDirectoryKey,
            ])

            results.append(PickedFileInfo(
                bookmarkId: bookmarkId,
                name: url.lastPathComponent,
                isDirectory: rv?.isDirectory ?? false,
                size: rv?.fileSize,
                contentType: rv?.contentType?.identifier,
                modificationDate: rv?.contentModificationDate,
                creationDate: rv?.creationDate
            ))
        }

        return results
    }

    // MARK: - Export

    public func exportFile(filename: String, data: Data) async -> Bool {
        guard let vc = topViewController else { return false }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do { try data.write(to: tempURL) } catch { return false }

        // Use asCopy: false (move mode) so the temp file is moved to the
        // user-chosen destination on success. This lets us reliably detect
        // whether the export succeeded by checking if the temp file is gone,
        // regardless of which delegate callback iOS fires (some iOS versions
        // call documentPickerWasCancelled even after a successful export
        // when using asCopy: true).
        let _: Bool = await withCheckedContinuation { continuation in
            let coordinator = PickerCoordinator(exportContinuation: continuation)
            self.activeCoordinator = coordinator

            let picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: false)
            picker.delegate = coordinator
            vc.present(picker, animated: true)
        }
        self.activeCoordinator = nil

        // With asCopy: false the system moves the file on success.
        // If the temp file is gone, the export succeeded.
        let exported = !FileManager.default.fileExists(atPath: tempURL.path)
        if !exported {
            try? FileManager.default.removeItem(at: tempURL)
        }
        return exported
    }

    // MARK: - Read File

    /// Read file data. If `subpath` is provided, reads a file relative to the bookmarked directory.
    public func readFileData(bookmarkId: String, subpath: String? = nil) -> Data? {
        guard let baseURL = resolveBookmark(bookmarkId) else { return nil }
        guard baseURL.startAccessingSecurityScopedResource() else { return nil }
        defer { baseURL.stopAccessingSecurityScopedResource() }

        let targetURL: URL
        if let subpath, !subpath.isEmpty {
            targetURL = baseURL.appendingPathComponent(subpath)
        } else {
            targetURL = baseURL
        }

        return try? Data(contentsOf: targetURL)
    }

    // MARK: - Write File

    /// Write data to a file. If `subpath` is provided, writes to a file relative to the bookmarked directory.
    public func writeFileData(bookmarkId: String, data: Data, subpath: String? = nil) -> Bool {
        guard let baseURL = resolveBookmark(bookmarkId) else { return false }
        guard baseURL.startAccessingSecurityScopedResource() else { return false }
        defer { baseURL.stopAccessingSecurityScopedResource() }

        let targetURL: URL
        if let subpath, !subpath.isEmpty {
            targetURL = baseURL.appendingPathComponent(subpath)
        } else {
            targetURL = baseURL
        }

        do {
            try data.write(to: targetURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - List Directory

    public func listDirectory(bookmarkId: String, recursive: Bool) -> [DirectoryEntry]? {
        guard let url = resolveBookmark(bookmarkId) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey]
        var entries: [DirectoryEntry] = []

        if recursive {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return nil }

            while let itemURL = enumerator.nextObject() as? URL {
                let rv = try? itemURL.resourceValues(forKeys: Set(keys))
                let relativePath = itemURL.path.replacingOccurrences(of: url.path + "/", with: "")
                entries.append(DirectoryEntry(
                    name: relativePath,
                    isDirectory: rv?.isDirectory ?? false,
                    size: rv?.fileSize,
                    contentType: rv?.contentType?.identifier,
                    modificationDate: rv?.contentModificationDate
                ))
            }
        } else {
            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return nil }

            for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let rv = try? itemURL.resourceValues(forKeys: Set(keys))
                entries.append(DirectoryEntry(
                    name: itemURL.lastPathComponent,
                    isDirectory: rv?.isDirectory ?? false,
                    size: rv?.fileSize,
                    contentType: rv?.contentType?.identifier,
                    modificationDate: rv?.contentModificationDate
                ))
            }
        }

        return entries
    }

    // MARK: - File Info

    /// Get file metadata. If `subpath` is provided, gets info for a file relative to the bookmarked directory.
    public func fileInfo(bookmarkId: String, subpath: String? = nil) -> [String: String]? {
        guard let baseURL = resolveBookmark(bookmarkId) else { return nil }
        guard baseURL.startAccessingSecurityScopedResource() else { return nil }
        defer { baseURL.stopAccessingSecurityScopedResource() }

        let url: URL
        if let subpath, !subpath.isEmpty {
            url = baseURL.appendingPathComponent(subpath)
        } else {
            url = baseURL
        }

        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .totalFileSizeKey,
            .creationDateKey, .contentModificationDateKey, .contentAccessDateKey,
            .contentTypeKey, .isDirectoryKey, .isRegularFileKey, .isHiddenKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadedKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemHasUnresolvedConflictsKey,
            .nameKey,
        ]

        guard let rv = try? url.resourceValues(forKeys: keys) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        var info: [String: String] = [:]
        info["name"] = url.lastPathComponent
        info["path"] = url.path
        info["is_directory"] = (rv.isDirectory ?? false) ? "yes" : "no"
        info["is_hidden"] = (rv.isHidden ?? false) ? "yes" : "no"
        if let size = rv.fileSize { info["size_bytes"] = "\(size)" }
        if let totalSize = rv.totalFileSize, totalSize != rv.fileSize {
            info["total_size_bytes"] = "\(totalSize)"
        }
        if let ct = rv.contentType { info["content_type"] = ct.identifier }
        if let created = rv.creationDate { info["created"] = isoFormatter.string(from: created) }
        if let modified = rv.contentModificationDate { info["modified"] = isoFormatter.string(from: modified) }
        if let accessed = rv.contentAccessDate { info["accessed"] = isoFormatter.string(from: accessed) }

        if rv.isUbiquitousItem == true {
            info["is_icloud"] = "yes"
            if let status = rv.ubiquitousItemDownloadingStatus {
                switch status {
                case .current: info["icloud_status"] = "current"
                case .downloaded: info["icloud_status"] = "downloaded"
                case .notDownloaded: info["icloud_status"] = "not_downloaded"
                default: info["icloud_status"] = "unknown"
                }
            }
            if let uploaded = rv.ubiquitousItemIsUploaded {
                info["icloud_uploaded"] = uploaded ? "yes" : "no"
            }
            if let uploading = rv.ubiquitousItemIsUploading {
                info["icloud_uploading"] = uploading ? "yes" : "no"
            }
            if let conflicts = rv.ubiquitousItemHasUnresolvedConflicts {
                info["icloud_conflicts"] = conflicts ? "yes" : "no"
            }
        }

        return info
    }

    // MARK: - Grants Management

    public func listGrants() -> [GrantInfo] {
        var results: [GrantInfo] = []
        for (id, data) in bookmarks {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) {
                results.append(GrantInfo(id: id, name: url.lastPathComponent, isValid: true))
            } else {
                results.append(GrantInfo(id: id, name: nil, isValid: false))
            }
        }
        return results.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    public func revokeGrant(_ id: String) -> Bool {
        guard bookmarks.removeValue(forKey: id) != nil else { return false }
        persistBookmarks()
        return true
    }

    /// Get the filename for a bookmarked file. If `subpath` is provided, returns the last component of the subpath.
    public func fileName(for bookmarkId: String, subpath: String? = nil) -> String? {
        guard let baseURL = resolveBookmark(bookmarkId) else { return nil }
        if let subpath, !subpath.isEmpty {
            return (subpath as NSString).lastPathComponent
        }
        return baseURL.lastPathComponent
    }
}

// MARK: - Picker Coordinator

@MainActor
private final class PickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private var pickContinuation: CheckedContinuation<[URL]?, Never>?
    private var exportContinuation: CheckedContinuation<Bool, Never>?

    init(pickContinuation: CheckedContinuation<[URL]?, Never>) {
        self.pickContinuation = pickContinuation
        super.init()
    }

    init(exportContinuation: CheckedContinuation<Bool, Never>) {
        self.exportContinuation = exportContinuation
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let cont = pickContinuation {
            pickContinuation = nil
            cont.resume(returning: urls)
        }
        if let cont = exportContinuation {
            exportContinuation = nil
            cont.resume(returning: !urls.isEmpty)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if let cont = pickContinuation {
            pickContinuation = nil
            cont.resume(returning: nil)
        }
        if let cont = exportContinuation {
            exportContinuation = nil
            cont.resume(returning: false)
        }
    }
}

#endif
