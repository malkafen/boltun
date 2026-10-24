import AppKit
import BoltunKit
import SwiftUI

struct ProfileAnchor: Hashable, Sendable {
    enum Surface: String, Sendable {
        case channel
        case thread
        case search
        case members
    }

    enum Kind: String, Sendable {
        case avatar
        case name
        case mention
        case member
    }

    var surface: Surface
    var kind: Kind
    var id: String
}

struct ProfilePopoverRequest: Hashable, Sendable {
    var userId: String
    var channelId: String?
    var overrideName: String?
    var overrideIconURL: URL?
    var hideStatus = false

    var hasOverride: Bool { overrideName != nil || overrideIconURL != nil }
}

struct ProfilePresentation: Equatable {
    var anchor: ProfileAnchor
    var request: ProfilePopoverRequest
    var point: CGPoint?
}

struct ProfilePopoverModel: Equatable {
    enum Role: String {
        case bot = "BOT"
        case guest = "GUEST"
        case systemAdmin = "System Admin"
        case teamAdmin = "Team Admin"
        case channelAdmin = "Channel Admin"
    }

    struct LocalTime: Equatable {
        var title: String
        var time: String
        var offset: String?
    }

    struct Status: Equatable {
        var emoji: String
        var glyph: String?
        var customEmojiId: String?
        var text: String
        var expiry: String?
    }

    var userId: String
    var username: String
    var fullName: String
    var botDescription: String?
    var position: String?
    var role: Role?
    var email: String?
    var lastOnline: String?
    var localTime: LocalTime?
    var customStatus: Status?
    var status: UserStatusValue?
    var isSelf: Bool
    var disclaimer: String?

    var usernameText: String { "@\(username)" }
    var showsMessageButton: Bool { !isSelf && disclaimer == nil }
    var showsSelfMessageButton: Bool { isSelf && disclaimer == nil }
    var hasDetails: Bool { email != nil || localTime != nil || customStatus != nil }

    static let maxPositionLength = 128
    static let lastOnlineWindow: TimeInterval = 7 * 86_400

    struct Facts {
        var myId: String
        var status: UserStatusValue?
        var lastActivity: Int64 = 0
        var isTeamAdmin = false
        var isChannelAdmin = false
        var config = ClientConfig(values: [:])
        var now: Date
        var calendar: Calendar
        var customEmojiId: (String) -> String? = { _ in nil }
    }

    static func make(user: User, request: ProfilePopoverRequest, facts: Facts) -> ProfilePopoverModel {
        let override = request.hasOverride
        return ProfilePopoverModel(
            userId: user.id,
            username: user.username,
            fullName: request.overrideName ?? user.fullName,
            botDescription: user.isBot && !override ? nonEmpty(user.botDescription) : nil,
            position: override ? nil : nonEmpty(String(user.position.prefix(maxPositionLength))),
            role: role(user: user, isTeamAdmin: facts.isTeamAdmin, isChannelAdmin: facts.isChannelAdmin),
            email: user.isBot || override ? nil : nonEmpty(user.email),
            lastOnline: lastOnline(user: user, facts: facts),
            localTime: override ? nil : localTime(user: user, now: facts.now, calendar: facts.calendar),
            customStatus: customStatus(user: user, request: request, facts: facts),
            status: request.hideStatus ? nil : facts.status ?? .offline,
            isSelf: user.id == facts.myId,
            disclaimer: override ? "This post was created by an integration from @\(user.username)" : nil
        )
    }

    static func role(user: User, isTeamAdmin: Bool, isChannelAdmin: Bool) -> Role? {
        if user.isBot { return .bot }
        if user.isGuest { return .guest }
        if user.isSystemAdmin { return .systemAdmin }
        if isTeamAdmin { return .teamAdmin }
        if isChannelAdmin { return .channelAdmin }
        return nil
    }

    static func localTime(user: User, now: Date, calendar: Calendar) -> LocalTime? {
        guard let identifier = user.currentTimezone else { return nil }
        let zone = timeZone(identifier)
        var profileCalendar = calendar
        profileCalendar.timeZone = zone
        let abbreviation = zoneAbbreviation(zone, identifier: identifier, at: now)
        return LocalTime(
            title: abbreviation.isEmpty ? "Local Time" : "Local Time (\(abbreviation))",
            time: TimeFormatting.time(now, calendar: profileCalendar),
            offset: offsetText(profile: zone, current: calendar.timeZone, at: now)
        )
    }

    static func timeZone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? .gmt
    }

    static func zoneAbbreviation(_ zone: TimeZone, identifier: String, at date: Date) -> String {
        if identifier.isEmpty || ["UTC", "Etc/UTC", "Etc/UCT", "UCT"].contains(identifier) { return "UTC" }
        return zone.abbreviation(for: date) ?? ""
    }

    static func offsetText(profile: TimeZone, current: TimeZone, at date: Date) -> String? {
        let difference = profile.secondsFromGMT(for: date) - current.secondsFromGMT(for: date)
        guard difference != 0 else { return nil }
        let hours = Double(abs(difference)) / 3600
        let amount = hours.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        return difference > 0 ? "(\(amount) hr ahead)" : "(\(amount) hr behind)"
    }

    static func customStatus(user: User, request: ProfilePopoverRequest, facts: Facts) -> Status? {
        guard facts.config.enableCustomUserStatuses, !request.hasOverride, !request.hideStatus,
              let status = user.customStatus, status.isSet, !status.isExpired(now: facts.now) else { return nil }
        let expiry = status.showsExpiry ? status.expiresAt.map { expiryText($0, now: facts.now, calendar: facts.calendar) } : nil
        return Status(
            emoji: status.emoji,
            glyph: status.emoji.isEmpty ? nil : EmojiGlyph.glyph(for: status.emoji),
            customEmojiId: status.emoji.isEmpty ? nil : facts.customEmojiId(status.emoji),
            text: status.text,
            expiry: expiry
        )
    }

    static func expiryText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = TimeFormatting.time(date, calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)?.addingTimeInterval(-0.001) ?? now
        if abs(date.timeIntervalSince(endOfToday)) < 1 { return "(Until Today)" }
        if calendar.isDate(date, inSameDayAs: now) { return "(Until \(time))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "(Until Tomorrow \(time))"
        }
        if let week = calendar.date(byAdding: .day, value: 7, to: startOfToday), date < week {
            return "(Until \(TimeFormatting.format(date, "EEEE", calendar: calendar)) \(time))"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = TimeFormatting.format(date, sameYear ? "MMM d" : "MMM d, yyyy", calendar: calendar)
        return "(Until \(day), \(time))"
    }

    static func lastOnline(user: User, facts: Facts) -> String? {
        guard facts.config.enableLastActiveTime, !user.isBot, user.showsLastActive,
              facts.status != .online, facts.lastActivity > 0 else { return nil }
        let elapsed = facts.now.timeIntervalSince(facts.lastActivity.mattermostDate)
        guard elapsed < lastOnlineWindow else { return nil }
        return "Last online \(relativeText(elapsed))"
    }

    static func relativeText(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, elapsed)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min. ago" }
        if seconds < 48 * 3600 { return "\(Int(seconds / 3600)) hr. ago" }
        return "\(Int(seconds / 86_400)) days ago"
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

extension Workspace {
    func showProfile(_ request: ProfilePopoverRequest, anchor: ProfileAnchor, point: CGPoint? = nil) {
        profilePopover = ProfilePresentation(anchor: anchor, request: request, point: point)
    }

    func hideProfile() {
        profilePopover = nil
    }

    func profileBinding(for anchor: ProfileAnchor) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.profilePopover?.anchor == anchor },
            set: { [weak self] shown in
                guard let self, !shown, profilePopover?.anchor == anchor else { return }
                profilePopover = nil
            }
        )
    }

    func profileRequest(for post: Post) -> ProfilePopoverRequest? {
        guard !post.isSystemMessage, !post.userId.isEmpty else { return nil }
        let fromWebhook = post.props["from_webhook"]?.boolValue == true
        let icon = fromWebhook ? post.props["override_icon_url"]?.stringValue ?? "" : ""
        return ProfilePopoverRequest(
            userId: post.userId,
            channelId: post.channelId,
            overrideName: post.overrideUsername,
            overrideIconURL: icon.isEmpty ? nil : URL(string: icon, relativeTo: session.client.baseURL)?.absoluteURL,
            hideStatus: fromWebhook
        )
    }

    func memberProfileRequest(userId: String, channelId: String) -> ProfilePopoverRequest {
        ProfilePopoverRequest(userId: userId, channelId: channelId)
    }

    var myTimeZone: TimeZone {
        guard let identifier = session.me?.currentTimezone, !identifier.isEmpty,
              session.me?.timezone["useAutomaticTimezone"] != "true",
              let zone = TimeZone(identifier: identifier) else { return calendar.timeZone }
        return zone
    }

    func profileModel(for request: ProfilePopoverRequest) -> ProfilePopoverModel? {
        guard let user = session.users[request.userId] else { return nil }
        let teamAdmin = session.currentTeamId.flatMap { session.teamMembership(teamId: $0, userId: user.id)?.schemeAdmin } ?? false
        let channelAdmin = rightPane != .search
            && (request.channelId.flatMap { session.channelMembership(channelId: $0, userId: user.id)?.schemeAdmin } ?? false)
        var profileCalendar = calendar
        profileCalendar.timeZone = myTimeZone
        let emojis = session.customEmojis
        let facts = ProfilePopoverModel.Facts(
            myId: session.myId,
            status: session.statuses[user.id],
            lastActivity: session.lastActivity[user.id] ?? 0,
            isTeamAdmin: teamAdmin,
            isChannelAdmin: channelAdmin,
            config: session.config,
            now: now(),
            calendar: profileCalendar,
            customEmojiId: { emojis[$0]?.id }
        )
        return ProfilePopoverModel.make(user: user, request: request, facts: facts)
    }

    func profileAvatarURL(for request: ProfilePopoverRequest) -> URL? {
        if let icon = request.overrideIconURL { return icon }
        let user = session.users[request.userId]
        return session.client.profileImageURL(userId: request.userId, lastPictureUpdate: user?.lastPictureUpdate ?? 0)
    }

    func messageFromProfile(_ request: ProfilePopoverRequest) async {
        profilePopover = nil
        await session.openDirect(userId: request.userId)
    }

    func showMentionProfile(name: String, anchor: ProfileAnchor, channelId: String?, point: CGPoint?) async {
        guard let user = await session.user(mentionName: name) else { return }
        showProfile(ProfilePopoverRequest(userId: user.id, channelId: channelId), anchor: anchor, point: point)
    }

    func sendEmail(_ address: String) {
        guard let url = URL(string: "mailto:\(address)") else { return }
        openExternal(url)
    }
}

struct ProfilePopoverView: View {
    let workspace: Workspace
    let request: ProfilePopoverRequest

    var body: some View {
        Group {
            if let model = workspace.profileModel(for: request) {
                ProfileCard(
                    model: model,
                    avatarURL: workspace.profileAvatarURL(for: request),
                    client: workspace.session.client,
                    onClose: { workspace.hideProfile() },
                    onMessage: { Task { await workspace.messageFromProfile(request) } },
                    onEmail: { workspace.sendEmail($0) }
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: ProfileCard.width, height: 140)
            }
        }
        .task(id: request) {
            await workspace.session.loadProfile(userId: request.userId, channelId: request.channelId)
        }
    }
}

struct ProfileCard: View {
    static let width: CGFloat = 288
    static let avatarSize: CGFloat = 96

    let model: ProfilePopoverModel
    let avatarURL: URL?
    let client: APIClient?
    let onClose: () -> Void
    let onMessage: () -> Void
    let onEmail: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            ProfileLargeAvatar(url: avatarURL, client: client, name: model.fullName.isEmpty ? model.username : model.fullName, status: model.status)
            if let lastOnline = model.lastOnline {
                Text(lastOnline)
                    .scaledFont(11.5)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
            }
            nameBlock.padding(.top, 10)
            if model.hasDetails {
                divider
                details
            }
            divider
            bottomRow
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
    }

    private var topRow: some View {
        HStack(spacing: 6) {
            if let role = model.role {
                RoleTag(text: role.rawValue)
            }
            Spacer(minLength: 0)
            IconButton(systemName: "xmark", help: "Close", size: 11, action: onClose)
                .accessibilityLabel("Close user profile popover")
        }
        .frame(height: 26)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !model.fullName.isEmpty {
                Text(model.fullName)
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .help(model.fullName)
            }
            if let description = model.botDescription {
                Text(description)
                    .scaledFont(13)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(model.usernameText)
                .scaledFont(model.fullName.isEmpty ? 17 : 13, weight: model.fullName.isEmpty ? .semibold : .regular)
                .foregroundStyle(model.fullName.isEmpty ? Theme.textPrimary : Theme.textSecondary)
                .textSelection(.enabled)
            if let position = model.position {
                Text(position)
                    .scaledFont(13)
                    .foregroundStyle(Theme.textSecondary)
                    .help(position)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let email = model.email {
                ProfileSection(title: "Email") {
                    Button(email) { onEmail(email) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(email)
                }
            }
            if let localTime = model.localTime {
                ProfileSection(title: localTime.title) {
                    HStack(spacing: 4) {
                        Text(localTime.time).foregroundStyle(Theme.textPrimary)
                        if let offset = localTime.offset {
                            Text(offset).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            if let status = model.customStatus {
                ProfileSection(title: "Status", accessory: status.expiry) {
                    HStack(spacing: 6) {
                        if !status.emoji.isEmpty {
                            EmojiGlyphView(name: status.emoji, glyph: status.glyph, customEmojiId: status.customEmojiId, client: client, size: 15)
                        }
                        Text(status.text)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        if let disclaimer = model.disclaimer {
            Text(disclaimer)
                .scaledFont(12)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.showsSelfMessageButton {
            ProfileActionButton(title: "Send yourself a message", systemImage: "paperplane", prominent: false, action: onMessage)
                .help("Send yourself a message")
        } else {
            ProfileActionButton(title: "Message", systemImage: "paperplane", prominent: true, action: onMessage)
                .help("Send message to \(model.username)")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}

struct ProfileLargeAvatar: View {
    let url: URL?
    let client: APIClient?
    let name: String
    let status: UserStatusValue?

    var body: some View {
        let size = ProfileCard.avatarSize
        RemoteImage(url: url, client: client, maxPixel: size * 2) {
            InitialsBadge(name: name, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if let status {
                StatusDot(status: status, size: 22, ring: Theme.popover)
                    .help(status.title)
                    .offset(x: -4, y: -4)
            }
        }
    }
}

struct RoleTag: View {
    let text: String

    var body: some View {
        Text(text)
            .scaledFont(10, weight: .semibold)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
    }
}

struct ProfileSection<Content: View>: View {
    let title: String
    var accessory: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(Theme.textPrimary).fontWeight(.semibold)
                if let accessory {
                    Text(accessory).foregroundStyle(Theme.textSecondary)
                }
            }
            .scaledFont(12)
            content().scaledFont(13)
        }
    }
}

struct ProfileActionButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(prominent ? Color.white : Theme.link)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 5).fill(background))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if prominent { return hovering ? Theme.accent.opacity(0.85) : Theme.accent }
        return Theme.link.opacity(hovering ? 0.16 : 0.08)
    }
}

struct ProfilePopoverTrigger<Label: View>: View {
    let workspace: Workspace
    let anchor: ProfileAnchor
    let request: ProfilePopoverRequest
    var arrowEdge: Edge = .trailing
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            workspace.showProfile(request, anchor: anchor)
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .popover(isPresented: workspace.profileBinding(for: anchor), arrowEdge: arrowEdge) {
            ProfilePopoverView(workspace: workspace, request: presentedRequest)
        }
    }

    private var presentedRequest: ProfilePopoverRequest {
        guard let presentation = workspace.profilePopover, presentation.anchor == anchor else { return request }
        return presentation.request
    }
}

@MainActor
final class PointerLocation {
    var point: CGPoint?
}

struct MentionProfileHost: ViewModifier {
    let workspace: Workspace
    let anchor: ProfileAnchor
    let channelId: String?
    @Environment(\.openURL) private var openURL
    @State private var pointer = PointerLocation()

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let location) = phase { pointer.point = location }
            }
            .environment(\.openURL, mentionAction)
            .background { MentionPopoverAnchor(workspace: workspace, anchor: anchor) }
    }

    private var mentionAction: OpenURLAction {
        let outer = openURL
        let pointer = pointer
        let workspace = workspace
        let anchor = anchor
        let channelId = channelId
        return OpenURLAction { url in
            if !Self.showProfile(for: url, workspace: workspace, anchor: anchor, channelId: channelId, point: pointer.point) {
                outer(url)
            }
            return .handled
        }
    }

    static func showProfile(for url: URL, workspace: Workspace, anchor: ProfileAnchor, channelId: String?, point: CGPoint?) -> Bool {
        guard case .mention(let name) = LinkRouter.action(for: url) else { return false }
        Task { await workspace.showMentionProfile(name: name, anchor: anchor, channelId: channelId, point: point) }
        return true
    }
}

struct MentionPopoverAnchor: View {
    let workspace: Workspace
    let anchor: ProfileAnchor

    var body: some View {
        let presentation = workspace.profilePopover?.anchor == anchor ? workspace.profilePopover : nil
        Color.clear
            .popover(isPresented: workspace.profileBinding(for: anchor), attachmentAnchor: attachment(presentation?.point), arrowEdge: .bottom) {
                if let presentation {
                    ProfilePopoverView(workspace: workspace, request: presentation.request)
                }
            }
    }

    private func attachment(_ point: CGPoint?) -> PopoverAttachmentAnchor {
        guard let point else { return .rect(.bounds) }
        return .rect(.rect(CGRect(x: point.x - 1, y: point.y - 8, width: 2, height: 16)))
    }
}

extension View {
    func mentionProfiles(workspace: Workspace, anchor: ProfileAnchor, channelId: String?) -> some View {
        modifier(MentionProfileHost(workspace: workspace, anchor: anchor, channelId: channelId))
    }
}
