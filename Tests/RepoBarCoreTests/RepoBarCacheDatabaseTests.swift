import Foundation
@testable import RepoBarCore
import Testing

#if os(Linux)
    @Suite("RepoBarCacheDatabase (Linux paths)")
    struct RepoBarCacheDatabaseTests {
        @Test("linuxCacheURL honours XDG_CACHE_HOME")
        func honoursXDG() {
            let url = HTTPResponseDiskCache.linuxCacheURL(
                env: ["XDG_CACHE_HOME": "/tmp/xdg-cache-test"],
                home: "/home/anyone"
            )
            #expect(url.path == "/tmp/xdg-cache-test/repobar/cache.sqlite")
        }

        @Test("linuxCacheURL falls back to ~/.cache/repobar/cache.sqlite")
        func fallback() {
            let url = HTTPResponseDiskCache.linuxCacheURL(
                env: [:],
                home: "/home/anyone"
            )
            #expect(url.path == "/home/anyone/.cache/repobar/cache.sqlite")
        }

        @Test("whitespace XDG_CACHE_HOME falls back to HOME")
        func emptyXDG() {
            let url = HTTPResponseDiskCache.linuxCacheURL(
                env: ["XDG_CACHE_HOME": "  "],
                home: "/home/anyone"
            )
            #expect(url.path == "/home/anyone/.cache/repobar/cache.sqlite")
        }
    }
#endif
