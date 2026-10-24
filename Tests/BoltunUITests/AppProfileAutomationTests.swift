import AppKit
import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

struct AppProfileCommandTests {
    func command(_ string: String) -> DebugCommand? {
        DebugCommand(url: URL(string: "boltun://debug/\(string)")!)
    }

    @Test func parsesMembersCommands() {
        #expect(command("members") == .members(on: nil))
        #expect(command("members?on=1") == .members(on: true))
        #expect(command("members?on=0") == .members(on: false))
        #expect(command("members-search?q=bo") == .membersSearch(query: "bo"))
        #expect(command("members-search") == .membersSearch(query: ""))
        #expect(command("members-more") == .membersMore)
        #expect(command("member-message?user=bob") == .memberMessage(username: "bob"))
        #expect(command("member-message") == nil)
    }

    @Test func parsesProfileCommands() {
        #expect(command("profile?close=1") == .profile(nil))
        #expect(command("profile-message") == .profileMessage)
        #expect(command("profile") == .profile(ProfileTarget(surface: .channel, kind: .avatar, index: 0)))
        #expect(command("profile?in=thread&target=name&index=2&post=p9") == .profile(ProfileTarget(surface: .thread, kind: .name, index: 2, postId: "p9")))
        #expect(command("profile?in=search&target=mention&user=bob") == .profile(ProfileTarget(surface: .search, kind: .mention, index: 0, username: "bob")))
        #expect(command("profile?in=members&user=bob") == .profile(ProfileTarget(surface: .members, kind: .member, index: 0, username: "bob")))
        #expect(command("profile?target=mention") == nil)
        #expect(command("profile?in=members") == nil)
        #expect(command("profile?in=members&target=avatar&user=bob") == nil)
        #expect(command("profile?target=member&user=bob") == nil)
        #expect(command("profile?in=sidebar") == nil)
        #expect(command("profile?target=face") == nil)
    }
}

@MainActor
struct AppProfileAutomationTests {
    static let users = #"[{"id":"me","username":"boltun","roles":"system_user"},{"id":"u2","username":"alice","first_name":"Alice","last_name":"Doe","email":"alice@example.com","roles":"system_user"},{"id":"u3","username":"carol","roles":"system_user"},{"id":"u4","username":"gone","delete_at":5}]"#
    static let memberships = #"[{"channel_id":"c1","user_id":"me","scheme_admin":false},{"channel_id":"c1","user_id":"u2","scheme_admin":false},{"channel_id":"c1","user_id":"u3","scheme_admin":true},{"channel_id":"c1","user_id":"u4"}]"#

    func harness() async -> Harness {
        let transport = FakeTransport()
        transport.set("GET users", Self.users)
        transport.set("POST channels/c1/members/ids", Self.memberships)
        transport.set("POST users/search", #"[{"id":"u2","username":"alice","first_name":"Alice","last_name":"Doe","email":"alice@example.com","position":"QA"}]"#)
        transport.set("GET channels/c1/stats", #"{"channel_id":"c1","member_count":3}"#)
        transport.set("GET users/u2", #"{"id":"u2","username":"alice","first_name":"Alice","last_name":"Doe","email":"alice@example.com","position":"QA"}"#)
        transport.set("GET users/me", #"{"id":"me","username":"boltun","notify_props":{"desktop":"mention"}}"#)
        transport.set("GET posts/p1/thread", FakeTransport.posts)
        transport.set("POST teams/t1/posts/search", FakeTransport.posts)
        let server = Harness.server()
        let harness = Harness(servers: [server], tokens: [server.id: "token"], transport: transport)
        await harness.model.startAll()
        return harness
    }

    func automation(_ harness: Harness) -> (DebugAutomation, LogSink) {
        let sink = LogSink()
        let automation = DebugAutomation(router: AppRouter(model: harness.model), host: FakeAutomationHost(), isEnabled: { true }) { sink.lines.append($0) }
        return (automation, sink)
    }

    func state(_ automation: DebugAutomation, _ sink: LogSink) async throws -> AutomationUIState {
        let path = "/tmp/boltun-tests-\(UUID().uuidString)-profile.json"
        await automation.handle(URL(string: "boltun://debug/state?path=\(path)")!)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return try #require(state.ui)
    }

    @Test func drivesMembersPaneAndProfiles() async throws {
        let harness = await harness()
        let (automation, sink) = automation(harness)
        func run(_ command: String) async -> String {
            await automation.handle(URL(string: "boltun://debug/\(command)")!)
            return sink.lines.last ?? ""
        }
        #expect(await run("members-search?q=a") == "error /members-search members pane is closed")
        #expect(await run("members") == "ok /members 3")
        var ui = try await state(automation, sink)
        #expect(ui.rightPane == "members")
        let members = try #require(ui.members)
        #expect(members.channel == "Town Square")
        #expect(members.count == 3)
        #expect(members.loaded == 4)
        #expect(!members.searchVisible)
        #expect(!members.canLoadMore)
        #expect(members.items == ["CHANNEL ADMINS", "carol [-]", "MEMBERS", "alice [-]", "boltun [-]"])
        #expect(await run("members-search?q=ali") == "ok /members-search 1")
        #expect(await run("members-more") == "ok /members-more 4")
        ui = try await state(automation, sink)
        #expect(ui.members?.search == "ali")
        #expect(ui.members?.searchVisible == true)
        #expect(await run("profile?in=members&user=alice") == "ok /profile u2")
        ui = try await state(automation, sink)
        let profile = try #require(ui.profile)
        #expect(profile.anchor == "members:member:u2")
        #expect(profile.loaded)
        #expect(profile.username == "@alice")
        #expect(profile.fullName == "Alice Doe")
        #expect(profile.position == "QA")
        #expect(profile.email == "alice@example.com")
        #expect(profile.button == "Message")
        #expect(!profile.isSelf)
        #expect(await run("profile?in=members&user=nobody") == "error /profile unknown user nobody")
        #expect(await run("profile-message") == "ok /profile-message dm1")
        ui = try await state(automation, sink)
        #expect(ui.profile == nil)
        #expect(await run("members?on=1") == "error /members no channel with members")
        #expect(await run("profile-message") == "error /profile-message no profile popover")
    }

    @Test func opensProfilesFromMessagesThreadsAndSearch() async throws {
        let harness = await harness()
        let (automation, sink) = automation(harness)
        func run(_ command: String) async -> String {
            await automation.handle(URL(string: "boltun://debug/\(command)")!)
            return sink.lines.last ?? ""
        }
        #expect(await run("profile?index=0") == "ok /profile me")
        var ui = try await state(automation, sink)
        #expect(ui.profile?.anchor == "channel:avatar:p2")
        #expect(ui.profile?.isSelf == true)
        #expect(ui.profile?.button == "Send yourself a message")
        #expect(await run("profile?target=name&post=p1") == "ok /profile me")
        ui = try await state(automation, sink)
        #expect(ui.profile?.anchor == "channel:name:p1")
        #expect(await run("profile?target=mention&user=alice.") == "ok /profile u2")
        ui = try await state(automation, sink)
        #expect(ui.profile?.anchor == "channel:mention:p2")
        #expect(await run("profile?target=mention&user=all") == "error /profile unknown mention")
        #expect(await run("profile?close=1") == "ok /profile")
        ui = try await state(automation, sink)
        #expect(ui.profile == nil)
        #expect(await run("profile?in=thread") == "error /profile no open thread")
        #expect(await run("open-thread?post=p1") == "ok /open-thread p1")
        #expect(await run("profile?in=thread&index=0&target=name") == "ok /profile me")
        #expect(await run("profile?in=thread&index=9") == "error /profile no thread post at index 9")
        #expect(await run("profile?in=search&index=0") == "error /profile no search result 0")
        #expect(await run("search?q=hello") == "ok /search 2")
        #expect(await run("profile?in=search&index=1&target=name") == "ok /profile me")
        ui = try await state(automation, sink)
        #expect(ui.profile?.anchor == "search:name:p1")
        #expect(await run("profile?in=search&post=p2") == "ok /profile me")
        #expect(await run("member-message?user=nobody") == "error /member-message unknown user nobody")
        let opened = await run("members")
        #expect(opened == "ok /members 3")
        #expect(await run("member-message?user=alice") == "ok /member-message dm1")
        ui = try await state(automation, sink)
        #expect(ui.rightPane == nil)
        #expect(await run("members?on=0") == "ok /members")
    }

    @Test func membersToggleClosesAgain() async throws {
        let harness = await harness()
        let (automation, sink) = automation(harness)
        await automation.handle(URL(string: "boltun://debug/members")!)
        await automation.handle(URL(string: "boltun://debug/members")!)
        #expect(sink.lines.last == "ok /members")
        let ui = try await state(automation, sink)
        #expect(ui.rightPane == nil)
        #expect(ui.members == nil)
        let session = try #require(harness.model.selectedSession)
        let workspace = AppRouter(model: harness.model).workspaces.workspace(for: session, serverURL: Harness.server().url)
        await #expect(throws: AutomationError.self) { try await automation.performProfile(.leave, workspace: workspace) }
    }
}
