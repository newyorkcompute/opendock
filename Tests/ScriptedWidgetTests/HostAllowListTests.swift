import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted host allow-list")
struct HostAllowListTests {
    @Test func matchesExactHostsWithoutCaringAboutCase() {
        #expect(ScriptedHostAllowList.matches(host: "API.GitHub.com", pattern: "api.github.com"))
        #expect(ScriptedHostAllowList.matches(host: "api.github.com", pattern: "API.GitHub.com"))
        #expect(!ScriptedHostAllowList.matches(host: "evil.github.com", pattern: "api.github.com"))
        #expect(!ScriptedHostAllowList.matches(host: "github.com", pattern: "api.github.com"))
        #expect(!ScriptedHostAllowList.matches(host: "api.github.com.evil.com", pattern: "api.github.com"))
    }

    @Test func wildcardMatchesLabelsInFrontOfTheSuffixOnly() {
        let pattern = "*.open-meteo.com"
        #expect(ScriptedHostAllowList.matches(host: "api.open-meteo.com", pattern: pattern))
        #expect(ScriptedHostAllowList.matches(host: "a.b.open-meteo.com", pattern: pattern))
        #expect(!ScriptedHostAllowList.matches(host: "open-meteo.com", pattern: pattern))
        #expect(!ScriptedHostAllowList.matches(host: "notopen-meteo.com", pattern: pattern))
        #expect(!ScriptedHostAllowList.matches(host: "open-meteo.com.evil.com", pattern: pattern))
        #expect(!ScriptedHostAllowList.matches(host: "api.open-meteo.org", pattern: pattern))
    }

    @Test func allowsAHostWhenAnyPatternMatches() {
        let patterns = ["api.github.com", "*.open-meteo.com"]
        #expect(ScriptedHostAllowList.allows(host: "api.github.com", patterns: patterns))
        #expect(ScriptedHostAllowList.allows(host: "archive-api.open-meteo.com", patterns: patterns))
        #expect(!ScriptedHostAllowList.allows(host: "example.com", patterns: patterns))
        #expect(!ScriptedHostAllowList.allows(host: "api.github.com", patterns: []))
    }

    @Test func acceptsExactHostsAndASingleLeadingWildcard() {
        #expect(ScriptedHostAllowList.isValidPattern("api.github.com"))
        #expect(ScriptedHostAllowList.isValidPattern("localhost"))
        #expect(ScriptedHostAllowList.isValidPattern("*.open-meteo.com"))
        #expect(ScriptedHostAllowList.isValidPattern("*.github.com"))
        #expect(!ScriptedHostAllowList.isValidPattern("*.com"))
        #expect(!ScriptedHostAllowList.isValidPattern("*"))
        #expect(!ScriptedHostAllowList.isValidPattern("*.*.com"))
        #expect(!ScriptedHostAllowList.isValidPattern("api.*.com"))
        #expect(!ScriptedHostAllowList.isValidPattern("https://api.github.com"))
        #expect(!ScriptedHostAllowList.isValidPattern("api.github.com/repos"))
        #expect(!ScriptedHostAllowList.isValidPattern(""))
        #expect(!ScriptedHostAllowList.isValidPattern("*.localhost"))
    }

    @Test func refusesAnythingButHTTPSOnADeclaredHost() {
        let patterns = ["api.github.com"]
        let listed = URL(string: "https://api.github.com/repos")!
        #expect(ScriptedHostAllowList.denial(of: listed, patterns: patterns) == nil)
        #expect(
            ScriptedHostAllowList.denial(of: URL(string: "http://api.github.com/")!, patterns: patterns) == .notHTTPS)
        #expect(
            ScriptedHostAllowList.denial(of: URL(string: "https://user:pw@api.github.com/")!, patterns: patterns)
                == .credentials)
        #expect(
            ScriptedHostAllowList.denial(of: URL(string: "https://evil.example/")!, patterns: patterns)
                == .hostNotAllowed("evil.example"))
        #expect(ScriptedHostAllowList.denial(of: URL(string: "https://api.github.com/")!, patterns: []) != nil)
    }
}
