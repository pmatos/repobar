import Foundation
@testable import RepoBarCore
import Testing

@Suite("LocalProjects")
struct LocalProjectsTests {
    @Test("PathFormatter.expandTilde turns ~/foo into HOME/foo")
    func expandTilde() {
        let expanded = PathFormatter.expandTilde("~/myproj")
        let home = NSHomeDirectory()
        #expect(expanded == "\(home)/myproj")
    }

    @Test("PathFormatter.expandTilde leaves non-~ paths alone")
    func expandTildeNoop() {
        #expect(PathFormatter.expandTilde("/tmp/abs") == "/tmp/abs")
        #expect(PathFormatter.expandTilde("relative/path") == "relative/path")
    }

    @Test("PathFormatter.abbreviateHome replaces HOME with ~")
    func abbreviateHome() {
        let home = NSHomeDirectory()
        #expect(PathFormatter.abbreviateHome("\(home)/repos/foo") == "~/repos/foo")
        #expect(PathFormatter.abbreviateHome("/tmp/elsewhere") == "/tmp/elsewhere")
    }

    @Test("discoverRepoRoots finds a .git working directory")
    func discoverRepoRoots() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // Create a fake repo at <root>/alpha/.git and a sibling non-repo at
        // <root>/beta/.
        let alphaGit = root
            .appendingPathComponent("alpha", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: alphaGit, withIntermediateDirectories: true)
        let beta = root.appendingPathComponent("beta", isDirectory: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)

        let service = LocalProjectsService()
        let found = await service.discoverRepoRoots(rootPath: root.path, maxDepth: 2)
        let foundPaths = Set(found.map { $0.standardizedFileURL.path })
        let alphaPath = root.appendingPathComponent("alpha").standardizedFileURL.path

        #expect(foundPaths.contains(alphaPath))
        #expect(foundPaths.contains(beta.standardizedFileURL.path) == false)
    }

    @Test("snapshot reports a real git repo's current branch")
    func snapshotReportsBranch() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("gamma", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        try runGit(in: repo, ["init", "--initial-branch=main", "-q"])
        try runGit(in: repo, ["config", "user.email", "test@example.com"])
        try runGit(in: repo, ["config", "user.name", "test"])
        let file = repo.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        try runGit(in: repo, ["add", "a.txt"])
        try runGit(in: repo, ["commit", "-m", "init", "-q"])

        let service = LocalProjectsService()
        let snapshot = await service.snapshot(
            rootPath: root.path,
            maxDepth: 2,
            autoSyncEnabled: false
        )

        let gamma = snapshot.statuses.first { $0.path.lastPathComponent == "gamma" }
        try #require(gamma != nil)
        #expect(gamma!.branch == "main")
    }
}

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("LocalProjectsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func runGit(in directory: URL, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = directory
    process.arguments = args
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        struct GitError: Error { let args: [String]; let code: Int32 }
        throw GitError(args: args, code: process.terminationStatus)
    }
}
