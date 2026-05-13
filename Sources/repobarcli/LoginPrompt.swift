import Foundation

struct LoginPrompt {
    let openURL: @Sendable (URL) throws -> Void
}

extension LoginPrompt {
    /// Builds a prompt that either opens the URL in the default browser or, when
    /// `noBrowser` is true, prints the URL on a series of lines for the user to
    /// paste into a browser manually.
    static func interactive(
        noBrowser: Bool,
        emit: @escaping @Sendable (String) -> Void = { Swift.print($0) }
    ) -> LoginPrompt {
        if noBrowser {
            return LoginPrompt { url in
                emit("Open this URL in a browser to authorize:")
                emit(url.absoluteString)
            }
        }
        return LoginPrompt { url in
            try repobarcli.openURL(url)
        }
    }
}
