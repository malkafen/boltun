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

    @Test func parsesServerManagementCommands() {
        #expect(command("boltun://debug/remove-server?server=1") == .removeServer(server: 1))
        #expect(command("boltun://debug/remove-server") == nil)
        #expect(command("boltun://debug/remove-server?server=-1") == nil)
        #expect(command("boltun://debug/setting?name=spellChecking&value=0") == .setting(name: "spellChecking", value: "0"))
        #expect(command("boltun://debug/setting?name=spellChecking") == nil)
        #expect(command("boltun://debug/setting?value=1") == nil)
    }

    @Test func parsesComposerCommands() {
        #expect(command("boltun://debug/send?text=hi%20there") == .send(text: "hi there", thread: false))
        #expect(command("boltun://debug/send?text=r&thread=1") == .send(text: "r", thread: true))
        #expect(command("boltun://debug/send?text=") == nil)
        #expect(command("boltun://debug/type?text=%40bo") == .type(text: "@bo", thread: false))
        #expect(command("boltun://debug/type") == .type(text: "", thread: false))
        #expect(command("boltun://debug/key?name=enter&mods=shift") == .key(name: "enter", modifiers: "shift", thread: false))
        #expect(command("boltun://debug/key?name=up&thread=true") == .key(name: "up", modifiers: "", thread: true))
        #expect(command("boltun://debug/key?name=space") == nil)
        #expect(command("boltun://debug/upload?path=/tmp/a.png&thread=yes") == .upload(path: "/tmp/a.png", thread: true))
        #expect(command("boltun://debug/upload?path=/etc/hosts") == nil)
        #expect(command("boltun://debug/edit-last?text=fixed") == .editLast(text: "fixed"))
        #expect(command("boltun://debug/edit-last") == nil)
        #expect(command("boltun://debug/delete-last") == .deleteLast)
    }

    @Test func parsesTimelineCommands() {
        #expect(command("boltun://debug/open-thread?index=2") == .openThread(index: 2, postId: nil))
        #expect(command("boltun://debug/open-thread?post=abc") == .openThread(index: 0, postId: "abc"))
        #expect(command("boltun://debug/close-pane") == .closePane)
        #expect(command("boltun://debug/react?index=1&emoji=smile") == .react(index: 1, emoji: "smile"))
        #expect(command("boltun://debug/react") == nil)
        #expect(command("boltun://debug/scroll?to=top") == .scroll(to: "top"))
        #expect(command("boltun://debug/scroll") == nil)
        #expect(command("boltun://debug/search?q=deploy") == .search(query: "deploy"))
        #expect(command("boltun://debug/search?q=") == nil)
        #expect(command("boltun://debug/jump?index=3") == .jump(index: 3))
        #expect(command("boltun://debug/jump") == .jump(index: 0))
    }

    @Test func parsesNavigationCommands() {
        #expect(command("boltun://debug/quickswitch?query=town&choose=1") == .quickSwitch(query: "town", choose: true, close: false))
        #expect(command("boltun://debug/quickswitch?close=1") == .quickSwitch(query: "", choose: false, close: true))
        #expect(command("boltun://debug/command?name=zoom-in") == .command(name: "zoom-in", number: nil))
        #expect(command("boltun://debug/command?name=team&number=2") == .command(name: "team", number: 2))
        #expect(command("boltun://debug/command") == nil)
        #expect(command("boltun://debug/join?channel=qa") == .join(channel: "qa"))
        #expect(command("boltun://debug/join") == nil)
        #expect(command("boltun://debug/leave") == .leave)
        #expect(command("boltun://debug/favorite") == .favorite(on: true))
        #expect(command("boltun://debug/favorite?on=0") == .favorite(on: false))
        #expect(command("boltun://debug/collapse?category=channels") == .collapse(category: "channels", collapsed: true))
        #expect(command("boltun://debug/collapse?category=channels&collapsed=0") == .collapse(category: "channels", collapsed: false))
        #expect(command("boltun://debug/collapse?category=channels&on=false") == .collapse(category: "channels", collapsed: false))
        #expect(command("boltun://debug/collapse") == nil)
        #expect(command("boltun://debug/link?url=https%3A%2F%2Fh%2Ft%2Fpl%2Fp") == .link(url: URL(string: "https://h/t/pl/p")!))
        #expect(command("boltun://debug/link?url=nope") == nil)
        #expect(command("boltun://debug/notification-click?server=1&team=t&channel=c&root=r") == .notificationClick(server: 1, team: "t", channel: "c", root: "r"))
        #expect(command("boltun://debug/notification-click?channel=c") == .notificationClick(server: 0, team: "", channel: "c", root: ""))
        #expect(command("boltun://debug/notification-click") == nil)
    }

    @Test func parsesFlags() {
        #expect(DebugCommand.flag("1"))
        #expect(DebugCommand.flag("TRUE"))
        #expect(DebugCommand.flag("on"))
        #expect(!DebugCommand.flag("0"))
        #expect(!DebugCommand.flag(""))
        #expect(!DebugCommand.flag(nil))
    }
}
