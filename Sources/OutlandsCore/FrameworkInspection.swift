import Foundation

/// Read-only evidence about Framework files. This never executes Wine or proves runtime usability.
public enum FrameworkInspection {
    public static func check(prefix: URL, framework: String) -> Diagnostic {
        let title = ".NET \(framework)"
        let folder = prefix.appendingPathComponent("drive_c/windows/Microsoft.NET/\(framework)/v4.0.30319")
        let dll = folder.appendingPathComponent("mscorlib.dll")
        guard Integrity.isPE(dll), let data = boundedRead(dll) else {
            return Diagnostic(title, false, "Framework assembly is missing, unreadable or not a Windows executable. Existing-game compatibility is not established by this check.")
        }
        // Wine Mono installs API/reference assemblies in both Framework directories. Their size
        // is not a reliable version check, and Mono can populate Microsoft's registry keys too.
        if containsUTF16(data, "Mono development team") || containsUTF16(data, "Various Mono authors") {
            return Diagnostic(title, false, "Wine Mono assembly detected. Microsoft .NET Framework is not verified; this does not mean your existing game is broken. An executable compatibility test was not performed.", severity: .information)
        }
        guard containsUTF16(data, "Microsoft Corporation"), Integrity.isPE(folder.appendingPathComponent("clr.dll")) else {
            return Diagnostic(title, false, "Framework files are present, but their runtime could not be identified. No runtime was executed. Do not rebuild a working game solely on this result.", severity: .warning)
        }
        guard let registry = boundedRead(prefix.appendingPathComponent("system.reg")),
              let text = String(data: registry, encoding: .utf8), release(in: text, framework: framework).map({ $0 >= 528040 }) == true else {
            return Diagnostic(title, false, "Microsoft Framework files are present; the matching .NET 4.8+ registry entry is not verified. This may be a legacy installation.", severity: .warning)
        }
        return Diagnostic(title, true, "Microsoft Framework files and a 4.8+ registry entry are present. Read-only evidence only; execution is tested during installation.")
    }

    static func release(in registry: String, framework: String) -> UInt32? {
        let suffix = #"Microsoft\\NET Framework Setup\\NDP\\v4\\Full"#
        let key = framework == "Framework" ? #"Software\\Wow6432Node\\"# + suffix : #"Software\\"# + suffix
        var selected = false
        var installed = false
        var value: UInt32?
        for line in registry.components(separatedBy: .newlines) {
            if line.hasPrefix("[") {
                if selected { break }
                selected = line.lowercased().hasPrefix("[" + key.lowercased() + "]")
            } else if selected {
                if line.lowercased() == #""Install"=dword:00000001"#.lowercased() { installed = true }
                let marker = #""Release"=dword:"#
                if line.lowercased().hasPrefix(marker.lowercased()) {
                    value = UInt32(line.dropFirst(marker.count), radix: 16)
                }
            }
        }
        return installed ? value : nil
    }

    private static func containsUTF16(_ data: Data, _ text: String) -> Bool {
        guard let marker = text.data(using: .utf16LittleEndian) else { return false }
        return data.range(of: marker) != nil
    }
    private static func boundedRead(_ url: URL) -> Data? {
        let limit = 64 * 1024 * 1024
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let bytes = try? file.read(upToCount: limit + 1), bytes.count <= limit else { return nil }
        return bytes
    }
}
