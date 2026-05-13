import Foundation

public enum RelativeFormatter {
    public static func string(from date: Date, relativeTo now: Date) -> String {
        #if canImport(Darwin)
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: now)
        #else
            // swift-corelibs-foundation does not ship RelativeDateTimeFormatter.
            // Manual approximation matching the macOS `.short` style closely
            // enough for menu display ("5m", "3h", "2d", etc.).
            let seconds = Int(now.timeIntervalSince(date))
            return Self.shortRelativeString(seconds: seconds)
        #endif
    }

    static func shortRelativeString(seconds: Int) -> String {
        let abs = Swift.abs(seconds)
        let suffix = seconds >= 0 ? " ago" : ""
        let prefix = seconds >= 0 ? "" : "in "

        let unit: (value: Int, suffix: String)
        switch abs {
        case 0 ..< 60:
            unit = (abs, "s")
        case 60 ..< 3600:
            unit = (abs / 60, "m")
        case 3600 ..< 86400:
            unit = (abs / 3600, "h")
        case 86400 ..< 604_800:
            unit = (abs / 86400, "d")
        case 604_800 ..< 2_592_000:
            unit = (abs / 604_800, "w")
        case 2_592_000 ..< 31_536_000:
            unit = (abs / 2_592_000, "mo")
        default:
            unit = (abs / 31_536_000, "y")
        }
        return "\(prefix)\(unit.value)\(unit.suffix)\(suffix)"
    }
}
