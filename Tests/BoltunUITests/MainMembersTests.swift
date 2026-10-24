import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
@testable import BoltunUI

private extension URLRequest {
    var queryMap: [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    var idsBody: [String] {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] } ?? []
    }
}

@MainActor
struct ChannelMemberListTests {
    static let users: [String: User] = [
        "a": User(id: "a", username: "zed", firstName: "Zed", lastName: "Admin"),
        "b": User(id: "b", username: "amy", firstName: "Amy", lastName: "Brown"),
        "c": User(id: "c", username: "bob.smith", firstName: "Bob", lastName: "Smith", nickname: "Builder Bob", email: "robert@corp.example"),
        "d": User(id: "d", username: "dora", deleteAt: 5),
        "e": User(id: "e", username: "eve", firstName: "Émile", lastName: "Zola"),
        "f": User(id: "f", username: "anna"),
    ]

    func source(nameDisplay: NameDisplaySetting = .fullName, admins: Set<String> = ["a"], members: Set<String> = ["a", "b", "c", "d", "e"]) -> ChannelMemberList.Source {
        ChannelMemberList.Source(
            users: Self.users,
            membership: { id in members.contains(id) ? ChannelMember(channelId: "town", userId: id, schemeAdmin: admins.contains(id)) : nil },
            statuses: ["b": .online, "c": .dnd],
            nameDisplay: nameDisplay
        )
    }

    @Test func entriesKeepActiveMembersAdminsFirstThenByName() {
        let entries = ChannelMemberList.entries(candidateIds: ["c", "b", "a", "d", "e", "f", "x", "b"], source: source(), term: "")
        #expect(entries.map(\.id) == ["a", "b", "c", "e"])
        #expect(entries.map(\.displayName) == ["Zed Admin", "Amy Brown", "Bob Smith", "Émile Zola"])
        #expect(entries[0].isAdmin)
        #expect(entries[1].status == .online)
        #expect(entries[0].status == nil)
        #expect(entries[1].showsUsername)
        let usernames = ChannelMemberList.entries(candidateIds: ["c", "b"], source: source(nameDisplay: .username), term: "")
        #expect(usernames.map(\.displayName) == ["amy", "bob.smith"])
        #expect(!usernames[0].showsUsername)
        let tie = [ChannelMemberEntry(id: "2", displayName: "Same", username: "b", isAdmin: false, lastPictureUpdate: 0), ChannelMemberEntry(id: "1", displayName: "Same", username: "a", isAdmin: false, lastPictureUpdate: 0)]
        #expect(tie.sorted(by: ChannelMemberList.precedes).map(\.id) == ["1", "2"])
    }

    @Test func itemsInsertWebappSections() {
        let entries = ChannelMemberList.entries(candidateIds: ["a", "b", "c"], source: source(admins: ["a", "c"]), term: "")
        #expect(ChannelMemberList.items(entries).map(\.id) == ["section:CHANNEL ADMINS", "c", "a", "section:MEMBERS", "b"])
        let plain = ChannelMemberList.entries(candidateIds: ["b", "c"], source: source(admins: []), term: "")
        #expect(ChannelMemberList.items(plain).map(\.id) == ["section:MEMBERS", "b", "c"])
        let admins = ChannelMemberList.entries(candidateIds: ["a"], source: source(), term: "")
        #expect(ChannelMemberList.items(admins).map(\.id) == ["section:CHANNEL ADMINS", "a"])
        #expect(ChannelMemberList.items([]).isEmpty)
    }

    @Test func matcherFollowsFilterProfilesStartingWithTerm() {
        let bob = Self.users["c"]!
        for term in ["bob", "BOB.S", "smith", ".smith", "@bob", "Bob Sm", "builder", "robert", "robert@corp", "Smi", ""] {
            #expect(ChannelMemberList.matches(bob, term: term), "\(term)")
        }
        for term in ["obert", "corp", "mith", "ob", "example"] {
            #expect(!ChannelMemberList.matches(bob, term: term), "\(term)")
        }
        #expect(ChannelMemberList.matches(User(id: "x", username: "first_last-name"), term: "name"))
        #expect(ChannelMemberList.matches(User(id: "x", username: "first_last-name"), term: "-name"))
        let filtered = ChannelMemberList.entries(candidateIds: ["a", "b", "c", "e"], source: source(), term: "zo")
        #expect(filtered.map(\.id) == ["e"])
    }

    @Test func countAndSearchVisibility() {
        #expect(ChannelMemberList.countText(nil) == "Members")
        #expect(ChannelMemberList.countText(1) == "1 member")
        #expect(ChannelMemberList.countText(42) == "42 members")
        #expect(!ChannelMemberList.showsSearch(memberCount: 19, term: ""))
        #expect(ChannelMemberList.showsSearch(memberCount: 20, term: ""))
        #expect(ChannelMemberList.showsSearch(memberCount: 3, term: "a"))
        #expect(!ChannelMemberList.showsSearch(memberCount: nil, term: ""))
    }
}

@MainActor
struct ChannelMembersModelTests {
    static let total = 105

    nonisolated static func user(_ index: Int) -> User {
        User(id: String(format: "u%03d", index), username: String(format: "user%03d", index), firstName: "User", lastName: String(format: "%03d", index))
    }

    static func transport(total: Int = total, admins: Set<String> = ["u050", "u003"]) -> RoutedTransport {
        let transport = Fixture.transport()
        transport.on("GET", "users") { request in
            let query = request.queryMap
            let page = Int(query["page"] ?? "0") ?? 0
            let perPage = Int(query["per_page"] ?? "60") ?? 60
            let slice = (0..<total).dropFirst(page * perPage).prefix(perPage).map(user)
            return (200, try! MattermostJSON.encoder.encode(Array(slice)))
        }
        transport.on("POST", "channels/town/members/ids") { request in
            let ids = request.idsBody
            let members = ids.map { ChannelMember(channelId: "town", userId: $0, schemeAdmin: admins.contains($0)) }
            return (200, try! MattermostJSON.encoder.encode(members))
        }
        transport.on("POST", "users/status/ids") { request in
            let ids = request.idsBody
            return (200, try! MattermostJSON.encoder.encode(ids.map { UserStatus(userId: $0, status: .away) }))
        }
        transport.on("POST", "users/search") { request in
            let term = (body(request)["term"] as? String ?? "").lowercased()
            let found = (0..<total).map(user).filter { $0.username.hasPrefix(term) || $0.lastName.hasPrefix(term) }
            return (200, try! MattermostJSON.encoder.encode(found))
        }
        return transport
    }

    @Test func pagesLazilyWithWebappEndpoints() async throws {
        let transport = Self.transport()
        let workspace = Fixture.workspace(transport: transport)
        let model = ChannelMembersModel(channelId: "town", session: workspace.session, debounce: .zero)
        #expect(!model.canLoadMore(memberCount: 105))
        await model.start()
        #expect(model.memberIds.count == 100)
        #expect(model.nextPage == 1)
        let first = try #require(transport.requests("GET", "users").first).queryMap
        #expect(first == ["in_channel": "town", "page": "0", "per_page": "100", "sort": "admin"])
        #expect(transport.requests("POST", "channels/town/members/ids").count == 1)
        #expect(model.canLoadMore(memberCount: 105))
        #expect(!model.canLoadMore(memberCount: 100))
        let items = ChannelMemberList.items(model.entries())
        #expect(items.prefix(4).map(\.id) == ["section:CHANNEL ADMINS", "u003", "u050", "section:MEMBERS"])
        #expect(model.entries().first?.status == .away)
        await model.start()
        #expect(transport.requests("GET", "users").count == 1)
        await model.loadMore()
        #expect(model.memberIds.count == 105)
        #expect(model.reachedEnd)
        #expect(!model.canLoadMore(memberCount: nil))
        await model.loadMore()
        #expect(transport.requests("GET", "users").count == 2)
        #expect(transport.requests("GET", "users").last?.queryMap["page"] == "1")
    }

    @Test func searchIsDebouncedAndScopedToChannel() async throws {
        let transport = Self.transport()
        let workspace = Fixture.workspace(transport: transport)
        let model = ChannelMembersModel(channelId: "town", session: workspace.session, debounce: .milliseconds(40))
        await model.start()
        model.search("user1")
        model.search("user10")
        #expect(model.isSearching)
        await model.waitForSearch()
        let searches = transport.requests("POST", "users/search")
        #expect(searches.count == 1)
        #expect(searches.first.map(body)?["term"] as? String == "user10")
        #expect(searches.first.map(body)?["in_channel_id"] as? String == "town")
        #expect(!model.isSearching)
        #expect(model.searchResultIds == ["u100", "u101", "u102", "u103", "u104"])
        #expect(model.entries().map(\.username) == ["user100", "user101", "user102", "user103", "user104"])
        #expect(!model.canLoadMore(memberCount: 105))
        await model.loadMore()
        #expect(transport.requests("GET", "users").count == 1)
        model.search("   ")
        #expect(!model.isSearching)
        #expect(model.searchResultIds.isEmpty)
        #expect(model.entries().count == 100)
        model.search("@user05")
        await model.waitForSearch()
        #expect(model.entries().map(\.username).first == "user050")
        model.search("")
        #expect(model.trimmedTerm.isEmpty)
    }

    @Test func staleSearchResultsAreIgnored() async {
        let workspace = Fixture.workspace(transport: Self.transport())
        let model = ChannelMembersModel(channelId: "town", session: workspace.session, debounce: .zero)
        model.search("user00")
        model.search("")
        await model.runSearch("user00")
        #expect(model.searchResultIds.isEmpty)
    }

    @Test func reloadStartsOverAndFailuresKeepState() async {
        let transport = Self.transport(total: 3)
        let workspace = Fixture.workspace(transport: transport)
        let model = ChannelMembersModel(channelId: "town", session: workspace.session, debounce: .zero)
        await model.start()
        #expect(model.memberIds == ["u000", "u001", "u002"])
        #expect(model.reachedEnd)
        await model.reload()
        #expect(model.memberIds == ["u000", "u001", "u002"])
        #expect(transport.requests("GET", "users").count == 2)
        transport.on("GET", "users", status: 500, json: #"{"id":"boom","message":"boom","status_code":500}"#)
        await model.reload()
        #expect(model.memberIds.isEmpty)
        #expect(!model.isLoading)
        #expect(!model.reachedEnd)
    }
}

@MainActor
struct ChannelMembersWorkspaceTests {
    @Test func headerCountTogglesMembersPane() async {
        let workspace = Fixture.workspace(transport: ChannelMembersModelTests.transport())
        #expect(!workspace.showsMembers)
        workspace.toggleMembers()
        #expect(workspace.rightPane == .members)
        #expect(workspace.membersPanel?.channelId == "town")
        #expect(await eventually { workspace.memberCounts["town"] == 42 })
        workspace.toggleMembers()
        #expect(workspace.rightPane == nil)
        workspace.memberCounts["town"] = 7
        await workspace.refreshMemberCount(channelId: "town")
        #expect(workspace.memberCounts["town"] == 42)
    }

    @Test func openingMembersReplacesThread() async {
        let transport = ChannelMembersModelTests.transport()
        transport.on("GET", "posts/p1/thread", json: #"{"order":[],"posts":{}}"#)
        let workspace = Fixture.workspace(transport: transport)
        await workspace.openThread(rootId: "p1")
        workspace.openMembers()
        #expect(workspace.rightPane == .members)
        #expect(workspace.threadRootId == nil)
    }

    @Test func directMessagesHaveNoMembersButGroupsDo() async {
        let workspace = Fixture.workspace(transport: ChannelMembersModelTests.transport())
        workspace.session.currentChannelId = "dm-alice"
        #expect(workspace.membersChannel == nil)
        workspace.toggleMembers()
        #expect(workspace.rightPane == nil)
        workspace.session.currentChannelId = "gm"
        workspace.toggleMembers()
        #expect(workspace.rightPane == .members)
        let first = workspace.membersModel(channelId: "gm")
        #expect(workspace.membersModel(channelId: "gm") === first)
        #expect(workspace.membersModel(channelId: "town") !== first)
        workspace.session.currentChannelId = nil
        #expect(workspace.membersChannel == nil)
    }

    @Test func reopeningMembersStartsWithAnEmptySearch() async {
        let workspace = Fixture.workspace(transport: ChannelMembersModelTests.transport())
        workspace.openMembers()
        let first = workspace.membersModel(channelId: "town")
        first.search("al")
        workspace.closeRightPane()
        workspace.openMembers()
        let second = workspace.membersModel(channelId: "town")
        #expect(second !== first)
        #expect(second.searchTerm.isEmpty)
    }

    @Test func sendMessageOpensDirectChannelAndClosesPane() async {
        let transport = ChannelMembersModelTests.transport()
        transport.on("POST", "channels/direct", value: Fixture.channels()[5])
        transport.on("GET", "channels/dm-alice/members/me", value: Fixture.members()["dm-alice"]!)
        let workspace = Fixture.workspace(transport: transport)
        workspace.openMembers()
        workspace.showProfile(ProfilePopoverRequest(userId: "alice"), anchor: ProfileAnchor(surface: .members, kind: .member, id: "alice"))
        await workspace.messageMember(userId: "alice")
        #expect(workspace.rightPane == nil)
        #expect(workspace.profilePopover == nil)
        #expect(workspace.session.currentChannelId == "dm-alice")
    }

    @Test func rendersPaneHeaderButtonAndRows() async {
        let workspace = Fixture.workspace(transport: ChannelMembersModelTests.transport())
        workspace.memberCounts["town"] = 105
        workspace.openMembers()
        await workspace.membersModel(channelId: "town").start()
        let pane = await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 620), name: "members-pane")
        #expect(MainSnapshot.distinctColors(pane) > 4)
        let header = await MainSnapshot.render(ChannelHeader(workspace: workspace, channel: Fixture.channels()[0]), size: CGSize(width: 820, height: 60), name: "members-header")
        #expect(MainSnapshot.distinctColors(header) > 3)
        await MainSnapshot.render(ChannelMembersButton(count: nil, active: false) {}, size: CGSize(width: 60, height: 24))
        await MainSnapshot.render(ChannelMemberRow(workspace: workspace, channelId: "town", entry: ChannelMemberEntry(id: "alice", displayName: "alice", username: "alice", status: .online, isAdmin: false, lastPictureUpdate: 0)), size: CGSize(width: 380, height: 48))
        workspace.membersModel(channelId: "town").search("zzz")
        await workspace.membersModel(channelId: "town").waitForSearch()
        await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 300), name: "members-no-results")
    }

    @Test func paneClosesWhenChannelBecomesDirect() async {
        let workspace = Fixture.workspace(transport: ChannelMembersModelTests.transport())
        workspace.openMembers()
        workspace.session.currentChannelId = "dm-alice"
        await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 200))
        #expect(workspace.rightPane == nil)
    }

    @Test func emptyAndLoadingStatesRender() async {
        let transport = ChannelMembersModelTests.transport(total: 0)
        let workspace = Fixture.workspace(transport: transport)
        workspace.memberCounts["town"] = 0
        workspace.openMembers()
        await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 200))
        #expect(await eventually { workspace.membersModel(channelId: "town").reachedEnd })
        await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 200))
    }
}
