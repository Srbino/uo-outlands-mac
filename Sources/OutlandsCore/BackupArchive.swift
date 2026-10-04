import Foundation
import Darwin
import CArchive

/// Inspect actual tar entries and file bodies rather than parsing a line-based `tar -t` listing.
/// External symlinks are preserved as links, but no member may be written beneath a link.
enum BackupArchive {
    struct Member {
        let type: mode_t
        let hardlink: String?
    }
    static func inspect(fd: Int32, expandedLimit: Int64, kind: BackupKind = .full) throws -> Int64 {
        guard lseek(fd, 0, SEEK_SET) >= 0, let reader = archive_read_new() else {
            throw InstallerError("Cannot read the backup archive.")
        }
        defer { archive_read_free(reader) }
        guard archive_read_support_filter_gzip(reader) == 0,
              archive_read_support_format_tar(reader) == 0,
              archive_read_open_fd(reader, fd, 256 * 1024) == 0 else {
            throw InstallerError("The backup is not a readable tar archive.")
        }
        var entries: [String: Member] = [:]
        var expanded: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)
        while true {
            try Task.checkCancellation()
            var entry: OpaquePointer?
            let status = archive_read_next_header(reader, &entry)
            if status == 1 { break } // ARCHIVE_EOF
            guard status == 0, let entry, let namePointer = archive_entry_pathname_utf8(entry),
                  let name = String(validatingUTF8: namePointer) else {
                throw InstallerError("The backup contains damaged or unsupported archive metadata.")
            }
            let path = try safePath(name)
            let key = canonical(path)
            guard entries.count < 500_000, entries[key] == nil else {
                throw InstallerError("The backup has duplicate paths or too many entries.")
            }
            let type = archive_entry_filetype(entry)
            if kind == .settings, !SettingsBackup.permits(key, directory: type == S_IFDIR) {
                throw InstallerError("A settings backup contains files outside its supported settings locations.")
            }
            let hardlink = try archive_entry_hardlink_utf8(entry).map { pointer -> String in
                guard let target = String(validatingUTF8: pointer) else { throw InstallerError("Invalid backup link.") }
                return canonical(try safePath(target))
            }
            guard [mode_t(S_IFREG), mode_t(S_IFDIR), mode_t(S_IFLNK)].contains(type) || hardlink != nil else {
                throw InstallerError("Backups may contain only files, directories and links, not devices or pipes.")
            }
            if type == S_IFLNK {
                guard let pointer = archive_entry_symlink_utf8(entry), let target = String(validatingUTF8: pointer),
                      !target.isEmpty, !target.contains("\n"), !target.contains("\r") else {
                    throw InstallerError("Invalid backup symbolic link.")
                }
            }
            // Paths used to locate the app must always be real directories/a regular plist.
            if key == "outlands.app" || key == "outlands.app/contents" {
                guard type == S_IFDIR, hardlink == nil else { throw InstallerError("The backup application root is redirected.") }
            }
            if key == "outlands.app/contents/info.plist" {
                guard type == S_IFREG, hardlink == nil else { throw InstallerError("The backup application configuration is redirected.") }
            }
            entries[key] = Member(type: type, hardlink: hardlink)
            let size = archive_entry_size(entry)
            guard size >= 0 else { throw InstallerError("Invalid backup entry size.") }
            if type == S_IFREG && hardlink == nil {
                let sum = expanded.addingReportingOverflow(size)
                guard !sum.overflow, sum.partialValue <= expandedLimit else {
                    throw InstallerError("The archive expands beyond its declared size. Nothing was restored.")
                }
                expanded = sum.partialValue
            } else if size != 0 {
                throw InstallerError("The backup contains unexpected data on a non-file entry.")
            }
            var read: Int64 = 0
            while true {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes { archive_read_data(reader, $0.baseAddress, $0.count) }
                guard count >= 0 else { throw InstallerError("The backup archive is truncated or damaged.") }
                if count == 0 { break }
                read += Int64(count)
                guard read <= size else { throw InstallerError("Invalid backup file size.") }
            }
            guard read == size else { throw InstallerError("The backup contains an incomplete file.") }
        }
        guard kind == .settings ? !entries.isEmpty : entries["outlands.app/contents/info.plist"] != nil else {
            throw InstallerError("The backup does not contain an application configuration.")
        }
        for (path, member) in entries {
            try Task.checkCancellation()
            try checkParents(path, entries: entries)
            if let target = member.hardlink {
                var current = target
                var seen: Set<String> = [path]
                while true {
                    guard seen.insert(current).inserted, seen.count <= 256, let destination = entries[current] else {
                        throw InstallerError("The backup contains an invalid hard-link chain.")
                    }
                    try checkParents(current, entries: entries)
                    guard destination.type == S_IFREG || destination.hardlink != nil else {
                        throw InstallerError("A backup hard link points to a directory or symbolic link.")
                    }
                    if let next = destination.hardlink { current = next } else { break }
                }
            }
        }
        return expanded
    }
    private static func safePath(_ name: String) throws -> String {
        var path = name
        while path.hasSuffix("/") { path.removeLast() }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\n"), !path.contains("\r"),
              !path.contains("\\"), components.first == "outlands.app",
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw InstallerError("The backup contains an unsafe application path.")
        }
        return path
    }
    private static func canonical(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    private static func checkParents(_ path: String, entries: [String: Member]) throws {
        var components = path.split(separator: "/").map(String.init)
        while components.count > 1 {
            components.removeLast()
            if let parent = entries[components.joined(separator: "/")], parent.type != S_IFDIR || parent.hardlink != nil {
                throw InstallerError("The backup contains a file beneath a link or a non-directory.")
            }
        }
    }
}
