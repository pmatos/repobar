@testable import repobarcli
import Testing

@Suite("CLIHelp platform gating")
struct CLIHelpPlatformTests {
    static let macOSOnlyCommandLines = [
        "repobar local sync",
        "repobar local rebase",
        "repobar local reset",
        "repobar local branches",
        "repobar worktrees",
        "repobar open finder",
        "repobar open terminal",
        "repobar checkout",
    ]

    @Test
    func `root help lists every cross-platform command`() {
        let text = rootHelpText()
        for line in [
            "repobar [repos]",
            "repobar repo <owner/name>",
            "repobar issues <owner/name>",
            "repobar pulls <owner/name>",
            "repobar local [",
            "repobar archives list",
            "repobar settings show",
            "repobar login",
            "repobar logout",
        ] {
            #expect(text.contains(line), "help should mention: \(line)")
        }
    }

    #if os(macOS)
    @Test
    func `root help on macOS includes the local-action commands`() {
        let text = rootHelpText()
        for line in Self.macOSOnlyCommandLines {
            #expect(text.contains(line), "macOS help should mention: \(line)")
        }
    }
    #else
    @Test
    func `root help on Linux omits the macOS-only local-action commands`() {
        let text = rootHelpText()
        for line in Self.macOSOnlyCommandLines {
            #expect(
                text.contains(line) == false,
                "Linux help must not advertise \(line)"
            )
        }
    }
    #endif
}
