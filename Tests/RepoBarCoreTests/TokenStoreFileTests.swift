import Foundation
@testable import RepoBarCore
import Testing

@Suite("TokenStore file storage")
struct TokenStoreFileTests {
    @Test("save then load round-trips tokens")
    func roundTripTokens() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TokenStore(service: "test.service", storage: .file(dir))

        let tokens = OAuthTokens(
            accessToken: "atok",
            refreshToken: "rtok",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.save(tokens: tokens)

        let loaded = try store.load()
        #expect(loaded == tokens)
    }

    @Test("save then load round-trips PATs")
    func roundTripPAT() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TokenStore(service: "test.service", storage: .file(dir))

        try store.savePAT("ghp_example12345")
        let loaded = try store.loadPAT()
        #expect(loaded == "ghp_example12345")
    }

    @Test("saved files have mode 0600")
    func savedFileIsRestrictive() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TokenStore(service: "test.service", storage: .file(dir))

        try store.savePAT("ghp_perm")
        // Inspect every file the store could have written; expect mode 0600.
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(urls.isEmpty == false)
        for url in urls {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let mode = attrs[.posixPermissions] as? NSNumber
            #expect(mode?.int16Value == 0o600, "expected 0o600 on \(url.lastPathComponent), got \(String(describing: mode))")
        }
    }

    #if os(Linux)
        @Test("load rejects token files that are not mode 0600 or stricter")
        func loadRejectsLoosePermissions() throws {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = TokenStore(service: "test.service", storage: .file(dir))

            try store.savePAT("ghp_initial")
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            try #require(urls.count == 1)
            let file = urls[0]

            // Loosen the permissions and attempt to load.
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

            #expect(throws: TokenStoreError.loadFailed) {
                _ = try store.loadPAT()
            }
        }

        @Test("default Linux file directory honours XDG_DATA_HOME")
        func defaultDirectoryHonoursXDG() {
            // Resolve via the same private path the default uses; we shadow the
            // environment, then call defaultFileDirectory().
            setenv("XDG_DATA_HOME", "/tmp/xdg-test-aaaa", 1)
            defer { unsetenv("XDG_DATA_HOME") }
            let dir = TokenStore.defaultFileDirectory().path
            #expect(dir.hasPrefix("/tmp/xdg-test-aaaa/repobar"))
        }

        @Test("default Linux file directory falls back to ~/.local/share/repobar")
        func defaultDirectoryFallback() throws {
            unsetenv("XDG_DATA_HOME")
            let dir = TokenStore.defaultFileDirectory().path
            let home = NSHomeDirectory()
            #expect(dir == "\(home)/.local/share/repobar")
        }
    #endif
}

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("TokenStoreFileTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
