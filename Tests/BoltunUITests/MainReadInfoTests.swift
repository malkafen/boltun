@testable import BoltunKit
import Foundation
import SwiftUI
import Testing
@testable import BoltunUI

extension Fixture {
    static let licensedValues = [
        "MaxPostSize": "16383",
        "PostPriority": "true",
        "PostAcknowledgements": "true",
        "AllowPersistentNotifications": "true",
        "PersistentNotificationIntervalMinutes": "5",
        "EnableBurnOnRead": "true",
        "BurnOnReadDurationSeconds": "600",
    ]

    static func readInfoPosts() -> [Post] {
        [
            Post(id: "ask", createAt: minutes(50), userId: "alice", channelId: "town", message: "Please confirm the rollout",
                 metadata: PostMetadata(priority: PostPriority(priority: .urgent, requestedAck: true), acknowledgements: [
                     PostAcknowledgement(userId: "bob", postId: "ask", acknowledgedAt: minutes(51)),
                 ])),
            Post(id: "mine-ack", createAt: minutes(52), userId: "me", channelId: "town", message: "Ack this please",
                 metadata: PostMetadata(priority: PostPriority(priority: .important, requestedAck: true))),
            Post(id: "burn-in", createAt: minutes(53), userId: "alice", channelId: "town", message: "", type: "burn_on_read",
                 props: ["read_duration": .number(600_000)]),
            Post(id: "burn-out", createAt: minutes(54), userId: "me", channelId: "town", message: "my secret", type: "burn_on_read",
                 props: ["read_duration": .number(600_000)], metadata: PostMetadata(recipients: ["bob"])),
        ]
    }

    @MainActor
    static func readInfoWorkspace() -> Workspace {
        let transport = transport()
        transport.on("POST", "users/me/posts/ask/ack", value: PostAcknowledgement(userId: "me", postId: "ask", acknowledgedAt: minutes(55), channelId: "town"))
        transport.on("DELETE", "users/me/posts/ask/ack", json: #"{"status":"OK"}"#)
        transport.on("GET", "posts/burn-in/reveal", value: Post(
            id: "burn-in", createAt: minutes(53), userId: "alice", channelId: "town", message: "the secret", type: "burn_on_read",
            props: ["read_duration": .number(600_000)], metadata: PostMetadata(expireAt: minutes(63))
        ))
        transport.on("DELETE", "posts/burn-out/burn", json: #"{"status":"OK"}"#)
        let workspace = workspace(transport: transport)
        let session = workspace.session
        session.now = { Fixture.now }
        session.config = ClientConfig(values: licensedValues)
        session.license = ClientLicense(values: ["IsLicensed": "true", "SkuShortName": "entry"])
        session.channelMemberCounts["town"] = 4
        for post in readInfoPosts() { session.posts[post.id] = post }
        session.timelines["town"]?.postIds += readInfoPosts().map(\.id)
        return workspace
    }
}

@MainActor
@Suite struct ReadInfoTextTests {
    @Test func priorityLabels() {
        #expect(PostPriorityText.label(.standard) == nil)
        #expect(PostPriorityText.label(.important) == "IMPORTANT")
        #expect(PostPriorityText.label(.urgent) == "URGENT")
        #expect(PostPriorityLevel.allCases.map(PostPriorityText.menuTitle) == ["Standard", "Important", "Urgent"])
        #expect(Set(PostPriorityLevel.allCases.map(PostPriorityText.icon)).count == 3)
        #expect(PostPriorityText.persistentNotificationsDescription(intervalMinutes: 1).contains("every 1 minute until"))
        #expect(PostPriorityText.persistentNotificationsDescription(intervalMinutes: 5).contains("every 5 minutes"))
    }

    @Test func acknowledgementTexts() {
        #expect(AcknowledgementText.authorHelp(count: 0) == "Nobody acknowledged this message yet")
        #expect(AcknowledgementText.authorHelp(count: 1) == "1 person acknowledged this message")
        #expect(AcknowledgementText.authorHelp(count: 4) == "4 people acknowledged this message")
        #expect(AcknowledgementText.popoverTitle(count: 0) == "Acknowledgements")
        #expect(AcknowledgementText.popoverTitle(count: 2) == "Acknowledgements (2)")
        let me = AcknowledgementPerson(id: "me", name: "Bolt Un", timeText: "now", isMe: true)
        #expect(AcknowledgementText.name(me) == "Bolt Un (you)")
        #expect(AcknowledgementText.name(AcknowledgementPerson(id: "a", name: "Alice", timeText: "now", isMe: false)) == "Alice")
    }

    @Test func acknowledgementRowStates() {
        var model = AcknowledgementRowModel(postId: "p", isAuthor: false, acknowledgedByMe: false, canToggle: true, people: [])
        #expect(!model.showsCount)
        #expect(model.buttonText == "Acknowledge")
        #expect(model.helpText == "Acknowledge this message")
        model.acknowledgedByMe = true
        #expect(model.helpText == "Remove your acknowledgement")
        model.canToggle = false
        #expect(model.helpText == "Acknowledged")
        model.people = [AcknowledgementPerson(id: "me", name: "Me", timeText: "now", isMe: true)]
        #expect(model.count == 1)
        #expect(model.showsCount)
        #expect(model.buttonText == "1")
        model.isAuthor = true
        #expect(model.helpText == "1 person acknowledged this message")
        model.people = []
        #expect(model.showsCount)
        #expect(model.buttonText == "0")
    }

    @Test func burnOnReadTexts() {
        #expect(BurnOnReadText.duration(millis: 0) == "less than 1 min")
        #expect(BurnOnReadText.duration(millis: 60_000) == "1 min")
        #expect(BurnOnReadText.duration(millis: 600_000) == "10 mins")
        #expect(BurnOnReadText.readReceipt(BurnOnReadReceipt(revealedCount: 1, totalRecipients: 1)) == "Read by 1 of 1 recipient")
        #expect(BurnOnReadText.readReceipt(BurnOnReadReceipt(revealedCount: 0, totalRecipients: 3)) == "Read by 0 of 3 recipients")
        #expect(BurnOnReadText.timeRemaining(millis: 0) == "00:00")
        #expect(BurnOnReadText.timeRemaining(millis: -5_000) == "00:00")
        #expect(BurnOnReadText.timeRemaining(millis: 1) == "00:01")
        #expect(BurnOnReadText.timeRemaining(millis: 59_000) == "00:59")
        #expect(BurnOnReadText.timeRemaining(millis: 600_000) == "10:00")
        #expect(BurnOnReadText.timeRemaining(millis: 3_600_000) == "1:00:00")
        #expect(BurnOnReadText.isWarning(millis: 60_000))
        #expect(!BurnOnReadText.isWarning(millis: 60_001))
        #expect(BurnOnReadText.timerHelp(millis: 90_000).hasPrefix("Deletes in 01:30"))
        #expect(BurnOnReadText.composerLabel(durationMinutes: 1) == "Burn on read · deleted 1 minute after it is opened")
        #expect(BurnOnReadText.composerLabel(durationMinutes: 10).contains("10 minutes"))
    }

    @Test func burnOnReadRowStates() {
        var model = BurnOnReadRowModel(postId: "p", authorName: "Alice", isSender: false, isRevealed: false, isRevealing: false, expireAt: 0, readDurationMillis: 600_000)
        #expect(model.showsPlaceholder)
        #expect(model.showsBadge)
        #expect(!model.showsTimer)
        #expect(model.badgeHelp.contains("Message will be deleted 10 mins after you view it"))
        model.readDurationMillis = 0
        #expect(model.badgeHelp == "Burn-on-read message")
        model.isRevealed = true
        #expect(!model.showsPlaceholder)
        #expect(!model.showsBadge)
        #expect(!model.showsTimer)
        model.expireAt = 500
        #expect(model.showsTimer)
        model.isSender = true
        model.isRevealed = false
        #expect(!model.showsPlaceholder)
        #expect(!model.showsBadge)
        model.expireAt = 0
        #expect(model.showsBadge)
        #expect(model.badgeHelp == "Click to delete message for everyone")
        model.receipt = BurnOnReadReceipt(revealedCount: 2, totalRecipients: 3)
        #expect(model.badgeHelp.hasSuffix("Read by 2 of 3 recipients"))
    }
}

@MainActor
@Suite struct ReadInfoRowTests {
    func context(_ workspace: Workspace) -> TimelineContext {
        var context = workspace.timelineContext(lastViewedAt: 0, showReplyContext: true)
        context.now = Fixture.now
        context.calendar = Fixture.calendar
        return context
    }

    func row(_ workspace: Workspace, _ postId: String) -> MessageRowModel {
        TimelineBuilder.row(for: workspace.session.posts[postId]!, previous: nil, continuation: false, context: context(workspace))
    }

    @Test func priorityAndAcknowledgementsAppearOnRows() {
        let workspace = Fixture.readInfoWorkspace()
        let ask = row(workspace, "ask")
        #expect(ask.priority == .urgent)
        let acknowledgement = ask.acknowledgement
        #expect(acknowledgement?.isAuthor == false)
        #expect(acknowledgement?.acknowledgedByMe == false)
        #expect(acknowledgement?.canToggle == true)
        #expect(acknowledgement?.people.map(\.name) == ["bob.smith"])
        #expect(acknowledgement?.people.first?.avatarURL != nil)
        #expect(acknowledgement?.people.first?.timeText.isEmpty == false)
        let mine = row(workspace, "mine-ack")
        #expect(mine.priority == .important)
        #expect(mine.acknowledgement?.isAuthor == true)
        #expect(mine.acknowledgement?.canToggle == false)
        #expect(row(workspace, "p1").acknowledgement == nil)
        #expect(row(workspace, "p1").priority == .standard)
    }

    @Test func featuresDisabledOnTheServerHideEverything() {
        let workspace = Fixture.readInfoWorkspace()
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "16383"])
        workspace.session.license = ClientLicense(values: [:])
        #expect(row(workspace, "ask").priority == .standard)
        #expect(row(workspace, "ask").acknowledgement == nil)
        #expect(row(workspace, "burn-in").burnOnRead == nil)
        #expect(!row(workspace, "burn-in").blocks.isEmpty == false)
    }

    @Test func acknowledgementIsHiddenForDeletedAndPendingPosts() {
        let workspace = Fixture.readInfoWorkspace()
        var context = context(workspace)
        var post = workspace.session.posts["ask"]!
        post.deleteAt = 5
        #expect(TimelineBuilder.acknowledgement(for: post, context: context) == nil)
        post.deleteAt = 0
        post.pendingPostId = post.id
        #expect(TimelineBuilder.acknowledgement(for: post, context: context) == nil)
        context.acknowledgementsEnabled = false
        #expect(TimelineBuilder.acknowledgement(for: workspace.session.posts["ask"]!, context: context) == nil)
    }

    @Test func burnOnReadRowsDescribeSenderAndRecipient() {
        let workspace = Fixture.readInfoWorkspace()
        let incoming = row(workspace, "burn-in").burnOnRead
        #expect(incoming?.isSender == false)
        #expect(incoming?.isRevealed == false)
        #expect(incoming?.showsPlaceholder == true)
        #expect(incoming?.readDurationMillis == 600_000)
        #expect(incoming?.receipt == nil)
        #expect(row(workspace, "burn-in").blocks.isEmpty)
        let outgoing = row(workspace, "burn-out").burnOnRead
        #expect(outgoing?.isSender == true)
        #expect(outgoing?.isRevealed == true)
        #expect(outgoing?.receipt == BurnOnReadReceipt(revealedCount: 1, totalRecipients: 3))
        #expect(!row(workspace, "burn-out").blocks.isEmpty)
    }

    @Test func revealingStateReachesTheRow() {
        let workspace = Fixture.readInfoWorkspace()
        workspace.session.revealingPostIds.insert("burn-in")
        #expect(row(workspace, "burn-in").burnOnRead?.isRevealing == true)
    }

    @Test func readInfoPostsNeverJoinTheGroupAbove() {
        let plain = Post(id: "1", createAt: 0, userId: "alice", channelId: "town", message: "x")
        let urgent = Post(id: "2", createAt: 1_000, userId: "alice", channelId: "town", message: "y", metadata: PostMetadata(priority: PostPriority(priority: .urgent)))
        let asking = Post(id: "3", createAt: 1_000, userId: "alice", channelId: "town", message: "y", metadata: PostMetadata(priority: PostPriority(requestedAck: true)))
        let burning = Post(id: "4", createAt: 1_000, userId: "alice", channelId: "town", message: "y", type: "burn_on_read")
        #expect(!TimelineBuilder.canGroup(urgent, after: plain))
        #expect(!TimelineBuilder.canGroup(asking, after: plain))
        #expect(!TimelineBuilder.canGroup(burning, after: plain))
        #expect(!TimelineBuilder.canGroup(plain, after: burning))
        #expect(TimelineBuilder.canGroup(Post(id: "5", createAt: 1_000, userId: "alice", channelId: "town", message: "y"), after: plain))
    }

    @Test func rowEqualityTracksReadInfo() {
        let workspace = Fixture.readInfoWorkspace()
        let model = row(workspace, "ask")
        var other = model
        other.priority = .important
        #expect(model != other)
        other = model
        other.acknowledgement?.canToggle = false
        #expect(model != other)
        other = model
        other.burnOnRead = BurnOnReadRowModel(postId: "ask", authorName: "a", isSender: false, isRevealed: false, isRevealing: false, expireAt: 0, readDurationMillis: 0)
        #expect(model != other)
    }
}

@MainActor
@Suite struct ReadInfoWorkspaceTests {
    @Test func acknowledgingGoesThroughTheSession() async {
        let workspace = Fixture.readInfoWorkspace()
        await workspace.toggleAcknowledgement(postId: "ask")
        #expect(workspace.session.posts["ask"]?.acknowledgedAt(by: "me") == Fixture.minutes(55))
    }

    @Test func revealingShowsTheMessage() async {
        let workspace = Fixture.readInfoWorkspace()
        let model = BurnOnReadRowModel(postId: "burn-in", authorName: "Alice", isSender: false, isRevealed: false, isRevealing: false, expireAt: 0, readDurationMillis: 600_000)
        workspace.burnOnReadActivated(model)
        #expect(await eventually { workspace.session.posts["burn-in"]?.message == "the secret" })
        #expect(workspace.pendingBurn == nil)
    }

    @Test func revealedMessagesAreNotRevealedTwice() async {
        let workspace = Fixture.readInfoWorkspace()
        var model = BurnOnReadRowModel(postId: "burn-in", authorName: "Alice", isSender: false, isRevealed: true, isRevealing: false, expireAt: 1, readDurationMillis: 0)
        workspace.burnOnReadActivated(model)
        model.postId = "nothing"
        workspace.burnOnReadActivated(model)
        #expect(workspace.session.posts["burn-in"]?.message.isEmpty == true)
    }

    @Test func senderConfirmsBeforeBurning() async {
        let workspace = Fixture.readInfoWorkspace()
        await workspace.openThread(rootId: "burn-out")
        workspace.burnOnReadActivated(BurnOnReadRowModel(postId: "burn-out", authorName: "Me", isSender: true, isRevealed: true, isRevealing: false, expireAt: 0, readDurationMillis: 0))
        #expect(workspace.pendingBurn?.id == "burn-out")
        await workspace.confirmBurn()
        #expect(workspace.pendingBurn == nil)
        #expect(workspace.session.posts["burn-out"] == nil)
        #expect(workspace.threadRootId == nil)
        await workspace.confirmBurn()
    }
}

@MainActor
@Suite struct ReadInfoComposerTests {
    func composer(_ workspace: Workspace, channelId: String = "town") -> ComposerState {
        workspace.composer(for: ComposerTarget(channelId: channelId))
    }

    @Test func pickerAppliesGatedPriority() {
        let workspace = Fixture.readInfoWorkspace()
        let state = composer(workspace)
        #expect(state.supportsPriority)
        #expect(!state.hasReadInfoLabels)
        state.apply(priority: PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true))
        #expect(state.priority == PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true))
        #expect(state.hasReadInfoLabels)
        state.apply(priority: PostPriority(priority: .important, requestedAck: true, persistentNotifications: true))
        #expect(state.priority == PostPriority(priority: .important, requestedAck: true))
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "16383", "PostPriority": "true"])
        state.apply(priority: PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true))
        #expect(state.priority == PostPriority(priority: .urgent))
        state.clearPriority()
        #expect(state.priority.isDefault)
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "16383"])
        #expect(!state.supportsPriority)
        state.apply(priority: PostPriority(priority: .urgent))
        #expect(state.priority.isDefault)
    }

    @Test func priorityIsOnlyForNewRootPosts() {
        let workspace = Fixture.readInfoWorkspace()
        let thread = workspace.composer(for: ComposerTarget(channelId: "town", rootId: "p1"))
        #expect(!thread.supportsPriority)
        #expect(!thread.supportsBurnOnRead)
        let state = composer(workspace)
        state.beginEditing(workspace.session.posts["p4"]!)
        #expect(!state.supportsPriority)
        #expect(!state.supportsBurnOnRead)
    }

    @Test func burnOnReadToggleFollowsTheChannel() {
        let workspace = Fixture.readInfoWorkspace()
        let state = composer(workspace)
        #expect(state.supportsBurnOnRead)
        state.setBurnOnRead(true)
        #expect(state.burnOnRead)
        #expect(state.hasReadInfoLabels)
        workspace.session.config = ClientConfig(values: ["MaxPostSize": "16383"])
        #expect(!state.supportsBurnOnRead)
        #expect(!state.hasReadInfoLabels)
        state.setBurnOnRead(false)
        #expect(!state.burnOnRead)
        state.setBurnOnRead(true)
        #expect(!state.burnOnRead)
    }

    @Test func sendingUsesAndClearsTheLabels() async throws {
        let workspace = Fixture.readInfoWorkspace()
        let transport = workspace.session.client.transport as! RoutedTransport
        transport.on("POST", "posts", status: 201, value: Post(
            id: "sent", createAt: Fixture.minutes(60), userId: "me", channelId: "town", message: "careful", type: "burn_on_read"
        ))
        let state = composer(workspace)
        state.apply(priority: PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true))
        state.setBurnOnRead(true)
        state.replaceText("careful")
        await state.send()
        #expect(state.priority.isDefault)
        #expect(!state.burnOnRead)
        let body = try #require(transport.requests("POST", "posts").last?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["type"] as? String == "burn_on_read")
        let priority = try #require((json["metadata"] as? [String: Any])?["priority"] as? [String: Any])
        #expect(priority["priority"] as? String == "urgent")
        #expect(priority["requested_ack"] as? Bool == true)
    }

    @Test func failedSendRestoresTheLabels() async {
        let workspace = Fixture.readInfoWorkspace()
        let transport = workspace.session.client.transport as! RoutedTransport
        transport.on("POST", "posts") { _ in (500, Data(#"{"message":"boom"}"#.utf8)) }
        let state = composer(workspace)
        state.apply(priority: PostPriority(priority: .important))
        state.setBurnOnRead(true)
        state.replaceText("careful")
        await state.send()
        #expect(state.priority == PostPriority(priority: .important))
        #expect(state.burnOnRead)
        #expect(state.text == "careful")
    }
}

@MainActor
@Suite struct ReadInfoViewTests {
    @Test func rendersPriorityAcknowledgementsAndBurnOnRead() async {
        let workspace = Fixture.readInfoWorkspace()
        var context = workspace.timelineContext(lastViewedAt: 0, showReplyContext: true)
        context.now = Fixture.now
        context.calendar = Fixture.calendar
        let rows = ["ask", "mine-ack", "burn-in", "burn-out"].map { id in
            TimelineBuilder.row(for: workspace.session.posts[id]!, previous: nil, continuation: false, context: context)
        }
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { model in
                MessageRow(model: model, workspace: workspace, hovering: true)
            }
            Spacer()
        }
        let rep = await MainSnapshot.render(view, size: CGSize(width: 680, height: 420), name: "read-info-rows")
        #expect(MainSnapshot.distinctColors(rep) > 6)
    }

    @Test func rendersBadgesButtonsAndTimers() async {
        let workspace = Fixture.readInfoWorkspace()
        let people = [AcknowledgementPerson(id: "bob", name: "Bob Smith", timeText: "10:04", isMe: false)]
        var toggled = 0
        var burned = 0
        let acknowledged = AcknowledgementRowModel(postId: "ask", isAuthor: false, acknowledgedByMe: true, canToggle: true, people: people)
        let pending = AcknowledgementRowModel(postId: "ask", isAuthor: false, acknowledgedByMe: false, canToggle: false, people: [])
        let timer = BurnOnReadRowModel(postId: "burn-out", authorName: "Me", isSender: true, isRevealed: true, isRevealing: false,
                                       expireAt: Fixture.now.mattermostMillis + 30_000, readDurationMillis: 600_000)
        let view = VStack(alignment: .leading, spacing: 10) {
            PostPriorityBadge(level: .important)
            PostPriorityBadge(level: .urgent)
            PostPriorityBadge(level: .standard)
            AcknowledgementButton(model: acknowledged, client: workspace.session.client, popoverShown: true) { toggled += 1 }
            AcknowledgementButton(model: pending, client: nil) { toggled += 1 }
            BurnOnReadBadge(model: timer) { burned += 1 }
            BurnOnReadTimerChip(model: timer, now: { Fixture.now }) { burned += 1 }
            BurnOnReadPlaceholder(model: BurnOnReadRowModel(postId: "burn-in", authorName: "Alice", isSender: false, isRevealed: false, isRevealing: true, expireAt: 0, readDurationMillis: 0)) {}
            Spacer()
        }
        .padding(12)
        let rep = await MainSnapshot.render(view, size: CGSize(width: 360, height: 400), name: "read-info-badges")
        #expect(MainSnapshot.distinctColors(rep) > 6)
        #expect(toggled == 0)
        #expect(burned == 0)
    }

    @Test func rendersPriorityPickerAndPopover() async {
        let workspace = Fixture.readInfoWorkspace()
        let state = workspace.composer(for: ComposerTarget(channelId: "town"))
        state.apply(priority: PostPriority(priority: .urgent, requestedAck: true, persistentNotifications: true))
        state.setBurnOnRead(true)
        let people = [
            AcknowledgementPerson(id: "me", name: "Bolt Un", timeText: "10:02", isMe: true),
            AcknowledgementPerson(id: "bob", name: "Bob Smith", timeText: "10:04", isMe: false),
        ]
        var applied: PostPriority?
        let view = VStack(alignment: .leading, spacing: 12) {
            ComposerReadInfoLabels(state: state)
            PostPriorityPickerButton(state: state)
            BurnOnReadToggleButton(state: state)
            PostPriorityPicker(
                priority: state.priority,
                acknowledgementsEnabled: true,
                persistentNotificationsEnabled: true,
                onCancel: {},
                onApply: { applied = $0 }
            )
            AcknowledgementPopover(model: AcknowledgementRowModel(postId: "ask", isAuthor: true, acknowledgedByMe: true, canToggle: false, people: people), client: workspace.session.client)
            BurnOnReadPlaceholder(model: BurnOnReadRowModel(postId: "burn-in", authorName: "Alice", isSender: false, isRevealed: false, isRevealing: false, expireAt: 0, readDurationMillis: 600_000)) {}
            Spacer()
        }
        .padding(12)
        let rep = await MainSnapshot.render(view, size: CGSize(width: 420, height: 620), name: "read-info-controls")
        #expect(MainSnapshot.distinctColors(rep) > 6)
        #expect(applied == nil)
    }
}
