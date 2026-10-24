import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunKit
import BoltunMarkup
@testable import BoltunUI

@MainActor
struct ProfilePopoverModelTests {
    static let statusConfig = ClientConfig(values: ["EnableCustomUserStatuses": "true", "EnableLastActiveTime": "true"])

    func facts(
        myId: String = "me",
        status: UserStatusValue? = .online,
        lastActivity: Int64 = 0,
        teamAdmin: Bool = false,
        channelAdmin: Bool = false,
        config: ClientConfig = statusConfig
    ) -> ProfilePopoverModel.Facts {
        ProfilePopoverModel.Facts(
            myId: myId,
            status: status,
            lastActivity: lastActivity,
            isTeamAdmin: teamAdmin,
            isChannelAdmin: channelAdmin,
            config: config,
            now: Fixture.now,
            calendar: Fixture.calendar,
            customEmojiId: { $0 == "partyparrot" ? "e1" : nil }
        )
    }

    func date(_ text: String) -> Date {
        try! Date(text, strategy: Date.ISO8601FormatStyle())
    }

    @Test func offsetTextDescribesHoursAheadOrBehind() {
        let utc = TimeZone(identifier: "UTC")!
        let now = Fixture.now
        #expect(ProfilePopoverModel.offsetText(profile: TimeZone(identifier: "Asia/Tokyo")!, current: utc, at: now) == "(9 hr ahead)")
        #expect(ProfilePopoverModel.offsetText(profile: TimeZone(identifier: "America/New_York")!, current: utc, at: now) == "(4 hr behind)")
        #expect(ProfilePopoverModel.offsetText(profile: TimeZone(identifier: "Asia/Kolkata")!, current: utc, at: now) == "(5.5 hr ahead)")
        #expect(ProfilePopoverModel.offsetText(profile: TimeZone(identifier: "Asia/Kathmandu")!, current: utc, at: now) == "(5.75 hr ahead)")
        #expect(ProfilePopoverModel.offsetText(profile: utc, current: TimeZone(identifier: "Asia/Kolkata")!, at: now) == "(5.5 hr behind)")
        #expect(ProfilePopoverModel.offsetText(profile: utc, current: TimeZone(identifier: "Etc/UTC")!, at: now) == nil)
    }

    @Test func localTimeUsesTheProfileZone() throws {
        let tokyo = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "false", "manualTimezone": "Asia/Tokyo"])
        let local = try #require(ProfilePopoverModel.localTime(user: tokyo, now: Fixture.now, calendar: Fixture.calendar))
        let abbreviation = TimeZone(identifier: "Asia/Tokyo")!.abbreviation(for: Fixture.now)!
        #expect(local.title == "Local Time (\(abbreviation))")
        #expect(local.time == "5:33 PM")
        #expect(local.offset == "(9 hr ahead)")
        let blank = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "true", "automaticTimezone": ""])
        let utc = try #require(ProfilePopoverModel.localTime(user: blank, now: Fixture.now, calendar: Fixture.calendar))
        #expect(utc.title == "Local Time (UTC)")
        #expect(utc.time == "8:33 AM")
        #expect(utc.offset == nil)
        let unknown = User(id: "u", username: "u", timezone: ["useAutomaticTimezone": "false", "manualTimezone": "Mars/Base"])
        #expect(ProfilePopoverModel.localTime(user: unknown, now: Fixture.now, calendar: Fixture.calendar)?.time == "8:33 AM")
        #expect(ProfilePopoverModel.localTime(user: User(id: "u", username: "u"), now: Fixture.now, calendar: Fixture.calendar) == nil)
        #expect(ProfilePopoverModel.zoneAbbreviation(.gmt, identifier: "Etc/UTC", at: Fixture.now) == "UTC")
    }

    @Test func rolesFollowWebappPrecedence() {
        let bot = User(id: "b", username: "b", roles: "system_admin system_user", isBot: true)
        let guest = User(id: "g", username: "g", roles: "system_guest")
        let admin = User(id: "a", username: "a", roles: "system_admin system_user")
        let user = User(id: "u", username: "u")
        #expect(ProfilePopoverModel.role(user: bot, isTeamAdmin: true, isChannelAdmin: true) == .bot)
        #expect(ProfilePopoverModel.role(user: guest, isTeamAdmin: true, isChannelAdmin: true) == .guest)
        #expect(ProfilePopoverModel.role(user: admin, isTeamAdmin: true, isChannelAdmin: true) == .systemAdmin)
        #expect(ProfilePopoverModel.role(user: user, isTeamAdmin: true, isChannelAdmin: true) == .teamAdmin)
        #expect(ProfilePopoverModel.role(user: user, isTeamAdmin: false, isChannelAdmin: true) == .channelAdmin)
        #expect(ProfilePopoverModel.role(user: user, isTeamAdmin: false, isChannelAdmin: false) == nil)
        #expect(ProfilePopoverModel.Role.systemAdmin.rawValue == "System Admin")
    }

    @Test func regularUserShowsNameEmailAndMessageButton() {
        let long = String(repeating: "p", count: 140)
        let user = User(id: "u2", username: "bob", firstName: "Bob", lastName: "Smith", nickname: "Bobby", email: "bob@example.com", position: long, timezone: ["useAutomaticTimezone": "false", "manualTimezone": "UTC"])
        let model = ProfilePopoverModel.make(user: user, request: ProfilePopoverRequest(userId: "u2"), facts: facts(teamAdmin: true))
        #expect(model.fullName == "Bob Smith")
        #expect(model.usernameText == "@bob")
        #expect(model.position?.count == 128)
        #expect(model.role == .teamAdmin)
        #expect(model.email == "bob@example.com")
        #expect(model.status == .online)
        #expect(model.localTime?.title == "Local Time (UTC)")
        #expect(model.hasDetails)
        #expect(model.showsMessageButton)
        #expect(!model.showsSelfMessageButton)
        #expect(model.disclaimer == nil)
        #expect(model.botDescription == nil)
        let bare = ProfilePopoverModel.make(user: User(id: "u3", username: "carol"), request: ProfilePopoverRequest(userId: "u3"), facts: facts(status: nil))
        #expect(bare.fullName.isEmpty)
        #expect(bare.position == nil)
        #expect(bare.email == nil)
        #expect(bare.status == .offline)
        #expect(!bare.hasDetails)
    }

    @Test func selfGetsSendYourselfAMessage() {
        let me = User(id: "me", username: "boltun")
        let model = ProfilePopoverModel.make(user: me, request: ProfilePopoverRequest(userId: "me"), facts: facts())
        #expect(model.isSelf)
        #expect(model.showsSelfMessageButton)
        #expect(!model.showsMessageButton)
    }

    @Test func botsShowBadgeAndDescriptionWithoutEmailOrLastOnline() {
        let bot = User(id: "b1", username: "playbooks", email: "bot@example.com", isBot: true, botDescription: "Playbooks bot.")
        let model = ProfilePopoverModel.make(user: bot, request: ProfilePopoverRequest(userId: "b1"), facts: facts(status: .offline, lastActivity: Fixture.baseTime))
        #expect(model.role == .bot)
        #expect(model.botDescription == "Playbooks bot.")
        #expect(model.email == nil)
        #expect(model.lastOnline == nil)
        #expect(model.showsMessageButton)
        let quiet = ProfilePopoverModel.make(user: User(id: "b2", username: "quiet", isBot: true), request: ProfilePopoverRequest(userId: "b2"), facts: facts())
        #expect(quiet.botDescription == nil)
    }

    @Test func webhookOverridesHideDetailsAndButtons() {
        let user = User(id: "u2", username: "bob", firstName: "Bob", email: "bob@example.com", position: "Engineer", timezone: ["manualTimezone": "UTC"], props: ["customStatus": #"{"text":"Busy"}"#])
        let request = ProfilePopoverRequest(userId: "u2", overrideName: "Deploy Bot", overrideIconURL: URL(string: "https://example.com/icon.png"), hideStatus: true)
        let model = ProfilePopoverModel.make(user: user, request: request, facts: facts())
        #expect(model.fullName == "Deploy Bot")
        #expect(model.disclaimer == "This post was created by an integration from @bob")
        #expect(model.email == nil)
        #expect(model.position == nil)
        #expect(model.localTime == nil)
        #expect(model.customStatus == nil)
        #expect(model.status == nil)
        #expect(!model.showsMessageButton)
        #expect(!model.showsSelfMessageButton)
        #expect(ProfilePopoverRequest(userId: "u", overrideIconURL: URL(string: "https://x")).hasOverride)
        #expect(!ProfilePopoverRequest(userId: "u").hasOverride)
    }

    @Test func customStatusRespectsConfigAndExpiry() throws {
        let expires = "2026-10-26T15:00:00Z"
        let user = User(id: "u2", username: "bob", props: ["customStatus": #"{"emoji":"partyparrot","text":"In a meeting","duration":"date_and_time","expires_at":"\#(expires)"}"#])
        let status = try #require(ProfilePopoverModel.make(user: user, request: ProfilePopoverRequest(userId: "u2"), facts: facts()).customStatus)
        #expect(status == ProfilePopoverModel.Status(emoji: "partyparrot", glyph: nil, customEmojiId: "e1", text: "In a meeting", expiry: "(Until 3:00 PM)"))
        let disabled = ProfilePopoverModel.make(user: user, request: ProfilePopoverRequest(userId: "u2"), facts: facts(config: ClientConfig(values: [:])))
        #expect(disabled.customStatus == nil)
        let hidden = ProfilePopoverModel.make(user: user, request: ProfilePopoverRequest(userId: "u2", hideStatus: true), facts: facts())
        #expect(hidden.customStatus == nil)
        let expired = User(id: "u2", username: "bob", props: ["customStatus": #"{"text":"Old","duration":"one_hour","expires_at":"2026-10-26T08:00:00Z"}"#])
        #expect(ProfilePopoverModel.make(user: expired, request: ProfilePopoverRequest(userId: "u2"), facts: facts()).customStatus == nil)
        let forever = User(id: "u2", username: "bob", props: ["customStatus": #"{"emoji":"coffee","text":"","duration":"dont_clear"}"#])
        let coffee = try #require(ProfilePopoverModel.make(user: forever, request: ProfilePopoverRequest(userId: "u2"), facts: facts()).customStatus)
        #expect(coffee.glyph == "☕")
        #expect(coffee.expiry == nil)
        let empty = User(id: "u2", username: "bob", props: ["customStatus": #"{"text":"","emoji":""}"#])
        #expect(ProfilePopoverModel.make(user: empty, request: ProfilePopoverRequest(userId: "u2"), facts: facts()).customStatus == nil)
    }

    @Test func expiryTextMatchesWebappWording() {
        let calendar = Fixture.calendar
        let now = Fixture.now
        func text(_ value: String) -> String { ProfilePopoverModel.expiryText(date(value), now: now, calendar: calendar) }
        #expect(ProfilePopoverModel.expiryText(date("2026-10-27T00:00:00Z").addingTimeInterval(-0.001), now: now, calendar: calendar) == "(Until Today)")
        #expect(text("2026-10-26T15:00:00Z") == "(Until 3:00 PM)")
        #expect(text("2026-10-27T09:30:00Z") == "(Until Tomorrow 9:30 AM)")
        #expect(text("2026-10-30T12:00:00Z") == "(Until Friday 12:00 PM)")
        #expect(text("2026-11-20T18:00:00Z") == "(Until Nov 20, 6:00 PM)")
        #expect(text("2027-01-05T18:00:00Z") == "(Until Jan 5, 2027, 6:00 PM)")
    }

    @Test func lastOnlineFollowsWebappRules() {
        let user = User(id: "u2", username: "bob")
        let now = Fixture.now.mattermostMillis
        func label(_ ago: Int64, status: UserStatusValue = .away, config: ClientConfig = Self.statusConfig, user: User = User(id: "u2", username: "bob")) -> String? {
            ProfilePopoverModel.lastOnline(user: user, facts: facts(status: status, lastActivity: now - ago, config: config))
        }
        #expect(label(30_000) == "Last online now")
        #expect(label(5 * 60_000) == "Last online 5 min. ago")
        #expect(label(3 * 3_600_000) == "Last online 3 hr. ago")
        #expect(label(47 * 3_600_000) == "Last online 47 hr. ago")
        #expect(label(3 * 86_400_000) == "Last online 3 days ago")
        #expect(label(8 * 86_400_000) == nil)
        #expect(label(60_000, status: .online) == nil)
        #expect(label(60_000, config: ClientConfig(values: [:])) == nil)
        #expect(label(60_000, user: User(id: "u2", username: "bob", props: ["show_last_active": "false"])) == nil)
        #expect(ProfilePopoverModel.lastOnline(user: user, facts: facts(status: .away, lastActivity: 0)) == nil)
        #expect(ProfilePopoverModel.relativeText(-5) == "now")
    }
}

@MainActor
struct ProfileWorkspaceTests {
    func transport() -> RoutedTransport {
        let transport = Fixture.transport()
        transport.on("POST", "channels/direct", value: Fixture.channels()[5])
        transport.on("GET", "channels/dm-alice/members/me", value: Fixture.members()["dm-alice"]!)
        transport.on("GET", "users/alice", value: Fixture.alice)
        transport.on("GET", "teams/t1/members/alice", json: #"{"team_id":"t1","user_id":"alice","scheme_admin":false}"#)
        transport.on("GET", "channels/town/members/alice", json: #"{"channel_id":"town","user_id":"alice","scheme_admin":true}"#)
        return transport
    }

    @Test func requestsComeFromPosts() throws {
        let workspace = Fixture.workspace()
        let posts = Fixture.townPosts()
        #expect(workspace.profileRequest(for: posts[0]) == nil)
        #expect(workspace.profileRequest(for: Post(id: "x", userId: "", channelId: "town", message: "hi")) == nil)
        let regular = try #require(workspace.profileRequest(for: posts[1]))
        #expect(regular == ProfilePopoverRequest(userId: "alice", channelId: "town"))
        let hook = Post(id: "h", userId: "bob", channelId: "town", message: "deployed", props: ["from_webhook": .string("true"), "override_username": .string("CI"), "override_icon_url": .string("/static/ci.png")])
        let request = try #require(workspace.profileRequest(for: hook))
        #expect(request.overrideName == "CI")
        #expect(request.overrideIconURL?.absoluteString == "http://mm.test/static/ci.png")
        #expect(request.hideStatus)
        #expect(workspace.profileAvatarURL(for: request) == request.overrideIconURL)
        #expect(workspace.profileAvatarURL(for: regular)?.path.hasSuffix("users/alice/image") == true)
        #expect(workspace.memberProfileRequest(userId: "bob", channelId: "town") == ProfilePopoverRequest(userId: "bob", channelId: "town"))
    }

    @Test func presentationStateAndBinding() {
        let workspace = Fixture.workspace()
        let anchor = ProfileAnchor(surface: .channel, kind: .avatar, id: "p1")
        let other = ProfileAnchor(surface: .thread, kind: .name, id: "p1")
        let binding = workspace.profileBinding(for: anchor)
        #expect(!binding.wrappedValue)
        workspace.showProfile(ProfilePopoverRequest(userId: "alice"), anchor: anchor, point: CGPoint(x: 4, y: 5))
        #expect(binding.wrappedValue)
        #expect(workspace.profilePopover?.point == CGPoint(x: 4, y: 5))
        #expect(!workspace.profileBinding(for: other).wrappedValue)
        workspace.profileBinding(for: other).wrappedValue = false
        #expect(workspace.profilePopover != nil)
        binding.wrappedValue = true
        #expect(workspace.profilePopover != nil)
        binding.wrappedValue = false
        #expect(workspace.profilePopover == nil)
        workspace.showProfile(ProfilePopoverRequest(userId: "alice"), anchor: anchor)
        workspace.hideProfile()
        #expect(workspace.profilePopover == nil)
    }

    @Test func modelCombinesSessionState() async throws {
        let workspace = Fixture.workspace(transport: transport())
        let session = workspace.session
        #expect(workspace.profileModel(for: ProfilePopoverRequest(userId: "ghost")) == nil)
        await session.loadProfile(userId: "alice", channelId: "town")
        let request = ProfilePopoverRequest(userId: "alice", channelId: "town")
        #expect(workspace.profileModel(for: request)?.role == .channelAdmin)
        workspace.rightPane = .search
        #expect(workspace.profileModel(for: request)?.role == nil)
        workspace.rightPane = nil
        session.teamRoster["t1"] = ["alice": TeamMember(teamId: "t1", userId: "alice", schemeAdmin: true)]
        #expect(workspace.profileModel(for: request)?.role == .teamAdmin)
        #expect(workspace.profileModel(for: ProfilePopoverRequest(userId: "alice"))?.status == .online)
    }

    @Test func myTimeZonePrefersManualSetting() {
        let workspace = Fixture.workspace()
        #expect(workspace.myTimeZone == Fixture.calendar.timeZone)
        workspace.session.me?.timezone = ["useAutomaticTimezone": "false", "manualTimezone": "Asia/Tokyo"]
        #expect(workspace.myTimeZone.identifier == "Asia/Tokyo")
        workspace.session.me?.timezone = ["useAutomaticTimezone": "true", "automaticTimezone": "Asia/Tokyo"]
        #expect(workspace.myTimeZone == Fixture.calendar.timeZone)
        workspace.session.me?.timezone = ["useAutomaticTimezone": "false", "manualTimezone": "Nowhere/Land"]
        #expect(workspace.myTimeZone == Fixture.calendar.timeZone)
    }

    @Test func messageButtonOpensDirectChannelAndCloses() async {
        let workspace = Fixture.workspace(transport: transport())
        let request = ProfilePopoverRequest(userId: "alice", channelId: "town")
        workspace.showProfile(request, anchor: ProfileAnchor(surface: .channel, kind: .avatar, id: "p1"))
        await workspace.messageFromProfile(request)
        #expect(workspace.profilePopover == nil)
        #expect(workspace.session.currentChannelId == "dm-alice")
    }

    @Test func mentionsResolveBeforePresenting() async {
        let transport = transport()
        transport.on("POST", "users/usernames", value: [User]())
        let workspace = Fixture.workspace(transport: transport)
        let anchor = ProfileAnchor(surface: .channel, kind: .mention, id: "p4")
        await workspace.showMentionProfile(name: "nobody", anchor: anchor, channelId: "town", point: nil)
        #expect(workspace.profilePopover == nil)
        await workspace.showMentionProfile(name: "alice.", anchor: anchor, channelId: "town", point: CGPoint(x: 10, y: 2))
        #expect(workspace.profilePopover == ProfilePresentation(anchor: anchor, request: ProfilePopoverRequest(userId: "alice", channelId: "town"), point: CGPoint(x: 10, y: 2)))
    }

    @Test func mentionLinksOpenTheProfileAndOtherLinksPassThrough() async {
        let workspace = Fixture.workspace(transport: transport())
        let anchor = ProfileAnchor(surface: .thread, kind: .mention, id: "p4")
        let web = URL(string: "https://example.com")!
        #expect(!MentionProfileHost.showProfile(for: web, workspace: workspace, anchor: anchor, channelId: "town", point: nil))
        #expect(MentionProfileHost.showProfile(for: MarkupLink.mentionURL("alice")!, workspace: workspace, anchor: anchor, channelId: "town", point: CGPoint(x: 4, y: 4)))
        #expect(await eventually { workspace.profilePopover?.request.userId == "alice" })
        #expect(workspace.profilePopover?.anchor == anchor)
    }

    @Test func emailOpensMailto() {
        let workspace = Fixture.workspace()
        var opened: [URL] = []
        workspace.openExternal = { opened.append($0) }
        workspace.sendEmail("alice@example.com")
        #expect(opened == [URL(string: "mailto:alice@example.com")!])
    }

    @Test func rendersCardsAndTriggers() async throws {
        let workspace = Fixture.workspace(transport: transport())
        workspace.session.config = ClientConfig(values: ["EnableCustomUserStatuses": "true", "EnableLastActiveTime": "true"])
        workspace.session.users["alice"]?.position = "Release Manager"
        workspace.session.users["alice"]?.email = "alice@example.com"
        workspace.session.users["alice"]?.timezone = ["useAutomaticTimezone": "false", "manualTimezone": "Asia/Tokyo"]
        workspace.session.users["alice"]?.props = ["customStatus": #"{"emoji":"calendar","text":"Planning","duration":"dont_clear"}"#]
        workspace.session.channelRoster["town"] = ["alice": ChannelMember(channelId: "town", userId: "alice", schemeAdmin: true)]
        let request = ProfilePopoverRequest(userId: "alice", channelId: "town")
        let card = await MainSnapshot.render(ProfilePopoverView(workspace: workspace, request: request).background(Theme.popover), size: CGSize(width: 288, height: 460), name: "profile-popover")
        #expect(MainSnapshot.distinctColors(card) > 4)
        let me = await MainSnapshot.render(ProfilePopoverView(workspace: workspace, request: ProfilePopoverRequest(userId: "me")).background(Theme.popover), size: CGSize(width: 288, height: 360), name: "profile-popover-self")
        #expect(MainSnapshot.distinctColors(me) > 3)
        let hook = ProfilePopoverRequest(userId: "bob", overrideName: "CI", hideStatus: true)
        await MainSnapshot.render(ProfilePopoverView(workspace: workspace, request: hook).background(Theme.popover), size: CGSize(width: 288, height: 360), name: "profile-popover-webhook")
        await MainSnapshot.render(ProfilePopoverView(workspace: workspace, request: ProfilePopoverRequest(userId: "ghost")), size: CGSize(width: 288, height: 160))
        let anchor = ProfileAnchor(surface: .channel, kind: .avatar, id: "p1")
        let trigger = ProfilePopoverTrigger(workspace: workspace, anchor: anchor, request: request) { Text("Alice") }
        await MainSnapshot.render(trigger, size: CGSize(width: 120, height: 40))
        workspace.showProfile(ProfilePopoverRequest(userId: "bob"), anchor: ProfileAnchor(surface: .channel, kind: .mention, id: "p4"), point: CGPoint(x: 20, y: 8))
        let mention = Text("Hi @alice").mentionProfiles(workspace: workspace, anchor: ProfileAnchor(surface: .channel, kind: .mention, id: "p4"), channelId: "town")
        await MainSnapshot.render(mention, size: CGSize(width: 200, height: 40))
        workspace.hideProfile()
    }

    @Test func messageListRendersProfileTriggers() async {
        let workspace = Fixture.workspace(transport: transport())
        let rep = await MainSnapshot.render(ChannelView(workspace: workspace), size: CGSize(width: 820, height: 640), name: "profile-triggers-channel")
        #expect(MainSnapshot.distinctColors(rep) > 6)
        workspace.searchResults = [Fixture.townPosts()[4], Fixture.townPosts()[0]]
        workspace.rightPane = .search
        await MainSnapshot.render(RightPaneView(workspace: workspace), size: CGSize(width: 380, height: 400), name: "profile-triggers-search")
    }
}
