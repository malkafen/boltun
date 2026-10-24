import Foundation
import Testing
@testable import BoltunUI

struct AppDebugCommandTests {
    func command(_ string: String) -> DebugCommand? {
        DebugCommand(url: URL(string: string)!)
    }

    @Test func recognizesDebugURLs() {
        #expect(DebugCommand.isDebugURL(URL(string: "boltun://debug/quit")!))
        #expect(DebugCommand.isDebugURL(URL(string: "BOLTUN://DEBUG/quit")!))
        #expect(!DebugCommand.isDebugURL(URL(string: "mattermost://debug/quit")!))
        #expect(!DebugCommand.isDebugURL(URL(string: "boltun://chat.example.com/team")!))
        #expect(command("mattermost://debug/quit") == nil)
    }

    @Test func parsesSnapshot() {
        #expect(command("boltun://debug/snapshot?path=/tmp/a.png") == .snapshot(path: "/tmp/a.png", window: .main))
        #expect(command("boltun://debug/snapshot?path=/tmp/x/b.png&window=settings") == .snapshot(path: "/tmp/x/b.png", window: .settings))
        #expect(command("boltun://debug/snapshot?path=/tmp/a.png&window=bogus") == .snapshot(path: "/tmp/a.png", window: .main))
        #expect(command("boltun://debug/snapshot?path=/etc/passwd") == nil)
        #expect(command("boltun://debug/snapshot") == nil)
    }

    @Test func restrictsOutputPaths() {
        #expect(DebugCommand.allowedPath("/tmp/a.png") == "/tmp/a.png")
        #expect(DebugCommand.allowedPath("/private/tmp/a.json") == "/private/tmp/a.json")
        #expect(DebugCommand.allowedPath("/tmp/../etc/passwd") == nil)
        #expect(DebugCommand.allowedPath("/tmp/a/../../etc/x") == nil)
        #expect(DebugCommand.allowedPath("tmp/a.png") == nil)
        #expect(DebugCommand.allowedPath("/tmp") == nil)
        #expect(DebugCommand.allowedPath("/tmp/") == nil)
        #expect(DebugCommand.allowedPath("/tmpfoo/a") == nil)
        #expect(DebugCommand.allowedPath("/Users/me/a.png") == nil)
    }

    @Test func parsesServerCommands() {
        #expect(command("boltun://debug/add-server?url=http://h:8065&name=Main") == .addServer(url: "http://h:8065", name: "Main"))
        #expect(command("boltun://debug/add-server?url=h&name=") == .addServer(url: "h", name: nil))
        #expect(command("boltun://debug/add-server") == nil)
        #expect(command("boltun://debug/login?server=1&user=u&password=p") == .login(server: 1, user: "u", password: "p"))
        #expect(command("boltun://debug/login?user=u&password=p") == .login(server: 0, user: "u", password: "p"))
        #expect(command("boltun://debug/login?server=-1&user=u&password=p") == .login(server: 0, user: "u", password: "p"))
        #expect(command("boltun://debug/login?user=u") == nil)
        #expect(command("boltun://debug/logout?server=2") == .logout(server: 2))
        #expect(command("boltun://debug/select?server=1&team=t&channel=c") == .select(server: 1, team: "t", channel: "c"))
        #expect(command("boltun://debug/select?team=") == .select(server: 0, team: nil, channel: nil))
    }

    @Test func parsesMiscCommands() {
        #expect(command("boltun://debug/state?path=/tmp/s.json") == .state(path: "/tmp/s.json"))
        #expect(command("boltun://debug/state?path=/var/s.json") == nil)
        #expect(command("boltun://debug/open?url=mattermost%3A%2F%2Fh%2Ft") == .open(url: URL(string: "mattermost://h/t")!))
        #expect(command("boltun://debug/open?url=nope") == nil)
        #expect(command("boltun://debug/present?sheet=login&server=1") == .present(sheet: "login", server: 1))
        #expect(command("boltun://debug/present") == nil)
        #expect(command("boltun://debug/settings?tab=about") == .settings(tab: .about))
        #expect(command("boltun://debug/settings") == .settings(tab: .servers))
        #expect(command("boltun://debug/dismiss") == .dismiss)
        #expect(command("boltun://debug/show") == .show)
        #expect(command("boltun://debug/close") == .close)
        #expect(command("boltun://debug/notify?title=T&body=B") == .notify(title: "T", body: "B"))
        #expect(command("boltun://debug/notify") == .notify(title: "Boltun", body: "Test notification"))
        #expect(command("boltun://debug/quit") == .quit)
        #expect(command("boltun://debug/unknown") == nil)
    }
}
