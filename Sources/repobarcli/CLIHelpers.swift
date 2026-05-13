import Commander
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif
import Foundation
import RepoBarCore

protocol CommanderRunnableCommand: ParsableCommand {
    static var commandName: String { get }
    mutating func bind(_ values: ParsedValues) throws
}

extension ParsableCommand {
    static func descriptor() -> CommandDescriptor {
        let description = Self.commandDescription
        let instance = Self()
        let signature = CommandSignature.describe(instance).flattened()
        let name = description.commandName ?? String(describing: Self.self).lowercased()
        let subcommands = description.subcommands.map { $0.descriptor() }
        let defaultName = description.defaultSubcommand?.commandDescription.commandName
            ?? description.defaultSubcommand.map { String(describing: $0).lowercased() }
        return CommandDescriptor(
            name: name,
            abstract: description.abstract,
            discussion: description.discussion,
            signature: signature,
            subcommands: subcommands,
            defaultSubcommandName: defaultName
        )
    }
}

extension ParsedValues {
    func flag(_ label: String) -> Bool {
        flags.contains(label)
    }

    func decodeOption<T: ExpressibleFromArgument>(_ label: String) throws -> T? {
        guard let raw = options[label]?.last else { return nil }
        guard let value = T(argument: raw) else {
            throw ValidationError("Invalid value for --\(label): \(raw)")
        }

        return value
    }

    func optionValues(_ label: String) -> [String] {
        options[label] ?? []
    }
}

struct OutputOptions: CommanderParsable {
    @Flag(
        names: [.customLong("json"), .customLong("json-output"), .short("j")],
        help: "Output JSON instead of the formatted table"
    )
    var jsonOutput: Bool = false

    @Flag(names: [.customLong("plain")], help: "Plain table output (no links, no colors, no URLs)")
    var plain: Bool = false

    @Flag(names: [.customLong("no-color")], help: "Disable color output")
    var noColor: Bool = false

    mutating func bind(_ values: ParsedValues) {
        self.jsonOutput = values.flag("jsonOutput")
        self.plain = values.flag("plain")
        self.noColor = values.flag("noColor")
    }

    var useColor: Bool {
        self.jsonOutput == false && self.plain == false && self.noColor == false && Ansi.supportsColor
    }
}

extension RepositorySortKey: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "activity", "act", "date":
            self = .activity
        case "issues", "issue", "iss":
            self = .issues
        case "prs", "pr", "pulls", "pull":
            self = .pulls
        case "stars", "star":
            self = .stars
        case "repo", "name":
            self = .name
        case "event", "activity-line", "line":
            self = .event
        default:
            return nil
        }
    }
}

extension GlobalActivityScope: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "all", "all-activity", "allactivity":
            self = .allActivity
        case "my", "mine", "my-activity", "myactivity":
            self = .myActivity
        default:
            return nil
        }
    }
}

enum CLIError: Error {
    case notAuthenticated
    case openFailed
    case toolMissing(String)
    case unknownCommand(String)

    var message: String {
        switch self {
        case .notAuthenticated:
            "No stored login. Run `repobar login` first."
        case .openFailed:
            "Failed to open the browser."
        case let .toolMissing(name):
            "Required tool '\(name)' was not found on PATH. Install it or use --no-browser to print the URL manually."
        case let .unknownCommand(command):
            "Unknown command: \(command)"
        }
    }
}

enum Ansi {
    static let reset = "\u{001B}[0m"
    static let bold = Code("\u{001B}[1m")
    static let red = Code("\u{001B}[31m")
    static let yellow = Code("\u{001B}[33m")
    static let magenta = Code("\u{001B}[35m")
    static let cyan = Code("\u{001B}[36m")
    static let gray = Code("\u{001B}[90m")
    static let oscTerminator = "\u{001B}\\"

    static var supportsColor: Bool {
        guard isatty(FileHandle.standardOutput.fileDescriptor) != 0 else { return false }

        return ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }

    static var supportsLinks: Bool {
        isatty(FileHandle.standardOutput.fileDescriptor) != 0
    }

    struct Code {
        let value: String

        init(_ value: String) {
            self.value = value
        }

        func wrap(_ text: String) -> String {
            "\(self.value)\(text)\(Ansi.reset)"
        }
    }

    static func link(_ label: String, url: URL, enabled: Bool) -> String {
        guard enabled else { return "\(label) \(url.absoluteString)" }

        let start = "\u{001B}]8;;\(url.absoluteString)\(Ansi.oscTerminator)"
        let end = "\u{001B}]8;;\(Ansi.oscTerminator)"
        return "\(start)\(label)\(end)"
    }
}

extension String {
    var singleLine: String {
        let noNewlines = self.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return noNewlines.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

func printError(_ message: String) {
    if Ansi.supportsColor {
        print(Ansi.red.wrap("Error: \(message)"))
    } else {
        print("Error: \(message)")
    }
}

func printJSON(_ output: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(output)
    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

struct URLOpenPlan: Equatable {
    let executable: String
    let arguments: [String]
    let needsPathLookup: Bool
}

func planURLOpen(_ url: URL) -> URLOpenPlan {
    #if canImport(Darwin)
        return URLOpenPlan(
            executable: "/usr/bin/open",
            arguments: [url.absoluteString],
            needsPathLookup: false)
    #else
        return URLOpenPlan(
            executable: "xdg-open",
            arguments: [url.absoluteString],
            needsPathLookup: true)
    #endif
}

func openURL(_ url: URL) throws {
    let plan = planURLOpen(url)
    try runOpenPlan(plan)
}

func runOpenPlan(_ plan: URLOpenPlan) throws {
    let process = Process()
    if plan.needsPathLookup {
        guard let path = lookupExecutable(plan.executable) else {
            throw CLIError.toolMissing(plan.executable)
        }
        process.executableURL = URL(fileURLWithPath: path)
    } else {
        process.executableURL = URL(fileURLWithPath: plan.executable)
    }
    process.arguments = plan.arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.openFailed }
}

func lookupExecutable(_ name: String) -> String? {
    if name.contains("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
    let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for dir in pathEnv.split(separator: ":") {
        let candidate = "\(dir)/\(name)"
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
}

func planOpenPath(_ path: String, application: String? = nil) -> URLOpenPlan {
    #if canImport(Darwin)
        let arguments: [String] = if let application, application.isEmpty == false {
            ["-a", application, path]
        } else {
            [path]
        }
        return URLOpenPlan(executable: "/usr/bin/open", arguments: arguments, needsPathLookup: false)
    #else
        if let application, application.isEmpty == false {
            return URLOpenPlan(executable: application, arguments: [path], needsPathLookup: true)
        }
        return URLOpenPlan(executable: "xdg-open", arguments: [path], needsPathLookup: true)
    #endif
}

func openPath(_ path: String, application: String? = nil) throws {
    try runOpenPlan(planOpenPath(path, application: application))
}

func parseHost(_ raw: String) throws -> URL {
    guard var components = URLComponents(string: raw) else {
        throw ValidationError("Invalid host: \(raw)")
    }

    if components.scheme == nil { components.scheme = "https" }
    guard let url = components.url else {
        throw ValidationError("Invalid host: \(raw)")
    }

    return url
}
