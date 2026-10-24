import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

struct AppDeepLinkTests {
    let alpha = ServerConfig(name: "Alpha", url: URL(string: "https://chat.example.com")!)
    let beta = ServerConfig(name: "Beta", url: URL(string: "http://192.168.15.101:8066")!)
    let gamma = ServerConfig(name: "Gamma", url: URL(string: "http://192.168.15.101:8065")!)
    let nested = ServerConfig(name: "Nested", url: URL(string: "https://example.org/mattermost")!)

    var servers: [ServerConfig] { [alpha, beta, gamma, nested] }

    func link(_ string: String) -> DeepLink? {
        DeepLink(url: URL(string: string)!)
    }

    @Test func parsesAppSchemes() {
        let parsed = link("mattermost://Chat.Example.com/team/channels/town-square")
        #expect(parsed == DeepLink(scheme: "mattermost", host: "chat.example.com", path: ["team", "channels", "town-square"]))
        #expect(parsed?.isWeb == false)
        #expect(link("boltun://chat.example.com:8443/team")?.port == 8443)
        #expect(link("https://chat.example.com/team/pl/abc")?.isWeb == true)
    }

    @Test func rejectsUnsupportedLinks() {
        #expect(link("ftp://chat.example.com/team") == nil)
        #expect(link("boltun://debug/snapshot?path=/tmp/a.png") == nil)
        #expect(DeepLink(url: URL(string: "mattermost:")!) == nil)
    }

    @Test func parsesRoutes() {
        #expect(DeepLinkRoute(components: []) == .server)
        #expect(DeepLinkRoute(components: ["team"]) == .team("team"))
        #expect(DeepLinkRoute(components: ["team", "channels"]) == .team("team"))
        #expect(DeepLinkRoute(components: ["team", "channels", "general"]) == .channel(team: "team", name: "general"))
        #expect(DeepLinkRoute(components: ["team", "pl", "p1"]) == .permalink(team: "team", postId: "p1"))
        #expect(DeepLinkRoute(components: ["team", "threads", "r1"]) == .thread(team: "team", rootId: "r1"))
        #expect(DeepLinkRoute(components: ["team", "messages", "@alice"]) == .direct(team: "team", username: "alice"))
        #expect(DeepLinkRoute(components: ["team", "messages", "abc123"]) == .groupMessage(team: "team", name: "abc123"))
        #expect(DeepLinkRoute(components: ["team", "emoji", "x"]) == .team("team"))
    }

    @Test func matchesServerByHost() {
        let match = link("mattermost://chat.example.com/team/channels/general")?.match(in: servers)
        #expect(match?.server == alpha)
        #expect(match?.route == .channel(team: "team", name: "general"))
    }

    @Test func matchesServerByPort() {
        #expect(link("mattermost://192.168.15.101:8065/a/channels/b")?.match(in: servers)?.server == gamma)
        #expect(link("mattermost://192.168.15.101:8066/a/channels/b")?.match(in: servers)?.server == beta)
        #expect(link("mattermost://192.168.15.101:9999/a")?.match(in: servers) == nil)
        #expect(link("mattermost://192.168.15.101/a")?.match(in: servers)?.server == beta)
    }

    @Test func matchesWebLinksRespectingPorts() {
        #expect(link("https://chat.example.com/team/pl/p1")?.match(in: servers)?.route == .permalink(team: "team", postId: "p1"))
        #expect(link("https://chat.example.com:443/team")?.match(in: servers)?.server == alpha)
        #expect(link("http://192.168.15.101:8065/team")?.match(in: servers)?.server == gamma)
        #expect(link("https://192.168.15.101/team")?.match(in: servers) == nil)
    }

    @Test func stripsServerSubpath() {
        let match = link("mattermost://example.org/mattermost/team/messages/@bob")?.match(in: servers)
        #expect(match?.server == nested)
        #expect(match?.route == .direct(team: "team", username: "bob"))
        #expect(link("mattermost://example.org/other/team")?.match(in: servers) == nil)
    }

    @Test func noMatchForUnknownHost() {
        #expect(link("mattermost://unknown.example.com/team")?.match(in: servers) == nil)
        #expect(DeepLink.defaultPort("ws") == nil)
    }
}
