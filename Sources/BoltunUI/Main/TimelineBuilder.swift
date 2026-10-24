import BoltunKit
import BoltunMarkup
import Foundation

struct ReplyContext: Equatable, Sendable {
    var rootId: String
    var authorName: String
    var snippet: String
}

struct ReactionChipModel: Equatable, Identifiable, Sendable {
    var id: String { emojiName }
    var emojiName: String
    var glyph: String?
    var customEmojiId: String?
    var count: Int
    var isMine: Bool
    var userNames: [String]
}

struct ThreadParticipant: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var avatarURL: URL?
}

struct ThreadSummary: Equatable, Sendable {
    static let maxParticipants = 3

    var replyCount: Int
    var participants: [ThreadParticipant]
    var lastReplyText: String
    var hasNewReplies: Bool

    var replyText: String { replyCount == 1 ? "1 reply" : "\(replyCount) replies" }
}

struct MessageRowModel: Equatable, Identifiable {
    var id: String { post.id }
    var post: Post
    var authorName: String
    var avatarURL: URL?
    var authorStatus: UserStatusValue?
    var isContinuation: Bool
    var isMine: Bool
    var mentionsMe: Bool
    var isSystem: Bool
    var replyContext: ReplyContext?
    var replyCount: Int
    var thread: ThreadSummary?
    var following: Bool?
    var reactions: [ReactionChipModel]
    var timeText: String
    var fullTimeText: String
    var blocks: [MessageBlock]
    var priority: PostPriorityLevel = .standard
    var acknowledgement: AcknowledgementRowModel?
    var burnOnRead: BurnOnReadRowModel?
    var readStatus: ReadStatusRowModel?

    static func == (lhs: MessageRowModel, rhs: MessageRowModel) -> Bool {
        lhs.post == rhs.post && lhs.authorName == rhs.authorName && lhs.avatarURL == rhs.avatarURL && lhs.authorStatus == rhs.authorStatus
            && lhs.isContinuation == rhs.isContinuation && lhs.isMine == rhs.isMine && lhs.mentionsMe == rhs.mentionsMe
            && lhs.replyContext == rhs.replyContext && lhs.replyCount == rhs.replyCount && lhs.thread == rhs.thread && lhs.reactions == rhs.reactions
            && lhs.following == rhs.following && lhs.timeText == rhs.timeText && lhs.priority == rhs.priority
            && lhs.acknowledgement == rhs.acknowledgement && lhs.burnOnRead == rhs.burnOnRead && lhs.readStatus == rhs.readStatus
    }
}

enum TimelineItem: Identifiable, Equatable {
    case date(String)
    case newMessages
    case replies(Int)
    case post(MessageRowModel)

    static let datePrefix = "date:"
    static let newMessagesId = "new-messages"
    static let repliesId = "replies"

    var id: String {
        switch self {
        case .date(let title): return Self.datePrefix + title
        case .newMessages: return Self.newMessagesId
        case .replies: return Self.repliesId
        case .post(let model): return model.post.id
        }
    }

    static func isPostId(_ id: String) -> Bool {
        !id.hasPrefix(datePrefix) && id != newMessagesId && id != repliesId
    }
}

struct TimelineContext {
    var myId: String
    var myUsername: String
    var mentionKeys: [String] = []
    var lastViewedAt: Int64 = 0
    var now: Date = Date()
    var calendar: Calendar = .current
    var showReplyContext = true
    var collapsedThreads = false
    var followThreads = false
    var postPriorityEnabled = false
    var acknowledgementsEnabled = false
    var burnOnReadEnabled = false
    var openThreadId: String?
    var readStates: [String: PostReadState] = [:]
    var canToggleAcknowledgement: (String) -> Bool = { _ in false }
    var burnOnReadReceipt: (String) -> BurnOnReadReceipt? = { _ in nil }
    var isRevealing: (String) -> Bool = { _ in false }
    var displayName: (Post) -> String = { $0.userId }
    var userName: (String) -> String = { $0 }
    var post: (String) -> Post? = { _ in nil }
    var avatarURL: (Post) -> URL? = { _ in nil }
    var userAvatarURL: (String) -> URL? = { _ in nil }
    var threadSeenAt: (String) -> Int64 = { _ in 0 }
    var status: (String) -> UserStatusValue? = { _ in nil }
    var isFollowing: (String) -> Bool = { _ in false }
    var customEmojiId: (String) -> String? = { _ in nil }
    var render: (Post) -> [MessageBlock] = { MessageRenderer.render($0.message) }
}

enum TimelineBuilder {
    static let groupingWindow: Int64 = 5 * 60 * 1000

    static func items(posts: [Post], context: TimelineContext) -> [TimelineItem] {
        var result: [TimelineItem] = []
        result.reserveCapacity(posts.count + 8)
        var previous: Post?
        var lastDayTitle: String?
        var insertedNewLine = false
        let readStatusIds = ReadStatusPlacement.postIds(posts: posts, states: context.readStates, myId: context.myId)
        for post in posts {
            var breaksGroup = false
            let date = post.createAt.mattermostDate
            let title = TimeFormatting.separatorTitle(for: date, now: context.now, calendar: context.calendar)
            if previous == nil || !context.calendar.isDate(date, inSameDayAs: previous!.createAt.mattermostDate) {
                if title != lastDayTitle {
                    result.append(.date(title))
                    lastDayTitle = title
                }
                breaksGroup = true
            }
            if !insertedNewLine, NewMessagesMarker.starts(at: post, lastViewedAt: context.lastViewedAt, myId: context.myId) {
                result.append(.newMessages)
                insertedNewLine = true
                breaksGroup = true
            }
            let continuation = !breaksGroup && previous.map { canGroup(post, after: $0) } == true
            let readStatus = readStatusIds.contains(post.id) ? context.readStates[post.id] : nil
            result.append(.post(row(for: post, previous: previous, continuation: continuation, context: context, readState: readStatus)))
            previous = post
        }
        return result
    }

    static func threadItems(posts: [Post], context: TimelineContext) -> [TimelineItem] {
        guard let root = posts.first, !root.isReply else { return items(posts: posts, context: context) }
        let replies = Array(posts.dropFirst())
        var result: [TimelineItem] = [.post(row(for: root, previous: nil, continuation: false, context: context))]
        guard !replies.isEmpty else { return result }
        result.append(.replies(replies.count))
        result.append(contentsOf: items(posts: replies, context: context).filter { if case .date = $0 { return false } else { return true } })
        return result
    }

    static func canGroup(_ post: Post, after previous: Post) -> Bool {
        guard post.userId == previous.userId, !post.isSystemMessage, !previous.isSystemMessage else { return false }
        guard !hasReadInfoHeader(post), !hasReadInfoHeader(previous) else { return false }
        guard post.overrideUsername == previous.overrideUsername else { return false }
        guard post.createAt - previous.createAt <= groupingWindow, post.createAt >= previous.createAt else { return false }
        if post.isReply { return post.rootId == previous.threadId }
        return !previous.isReply
    }

    static func hasReadInfoHeader(_ post: Post) -> Bool {
        post.priorityLevel.isLabelled || post.requestsAcknowledgement || post.isBurnOnRead
    }

    static func row(for post: Post, previous: Post?, continuation: Bool, context: TimelineContext, readState: PostReadState? = nil) -> MessageRowModel {
        let date = post.createAt.mattermostDate
        let isMine = post.userId == context.myId
        let burn = burnOnRead(for: post, context: context)
        return MessageRowModel(
            post: post,
            authorName: context.displayName(post),
            avatarURL: context.avatarURL(post),
            authorStatus: authorStatus(for: post, context: context),
            isContinuation: continuation,
            isMine: isMine,
            mentionsMe: !isMine && !post.isSystemMessage && MentionDetector.mentions(post.message, username: context.myUsername, keys: context.mentionKeys),
            isSystem: post.isSystemMessage,
            replyContext: context.showReplyContext ? replyContext(for: post, previous: previous, context: context) : nil,
            replyCount: post.isReply ? 0 : post.replyCount,
            thread: context.collapsedThreads ? threadSummary(for: post, context: context) : nil,
            following: following(for: post, context: context),
            reactions: reactions(for: post, context: context),
            timeText: TimeFormatting.time(date, calendar: context.calendar),
            fullTimeText: TimeFormatting.full(date, calendar: context.calendar),
            blocks: post.isDeleted || burn?.showsPlaceholder == true ? [] : context.render(post),
            priority: context.postPriorityEnabled ? post.priorityLevel : .standard,
            acknowledgement: acknowledgement(for: post, context: context),
            burnOnRead: burn,
            readStatus: readState.map { ReadStatusRowModel(state: $0, userName: context.userName) }
        )
    }

    static func acknowledgement(for post: Post, context: TimelineContext) -> AcknowledgementRowModel? {
        guard context.acknowledgementsEnabled, post.requestsAcknowledgement, !post.isDeleted, post.pendingPostId != post.id else { return nil }
        let people = post.acknowledgements.map { acknowledgement in
            AcknowledgementPerson(
                id: acknowledgement.userId,
                name: context.userName(acknowledgement.userId),
                timeText: TimeFormatting.short(acknowledgement.acknowledgedAt.mattermostDate, now: context.now, calendar: context.calendar),
                isMe: acknowledgement.userId == context.myId,
                avatarURL: context.userAvatarURL(acknowledgement.userId)
            )
        }
        return AcknowledgementRowModel(
            postId: post.id,
            isAuthor: post.userId == context.myId,
            acknowledgedByMe: post.acknowledgedAt(by: context.myId) != nil,
            canToggle: context.canToggleAcknowledgement(post.id),
            people: people
        )
    }

    static func burnOnRead(for post: Post, context: TimelineContext) -> BurnOnReadRowModel? {
        guard context.burnOnReadEnabled, post.isBurnOnRead, !post.isDeleted, post.pendingPostId != post.id else { return nil }
        let isSender = post.userId == context.myId
        return BurnOnReadRowModel(
            postId: post.id,
            authorName: context.displayName(post),
            isSender: isSender,
            isRevealed: post.isBurnOnReadRevealed(by: context.myId),
            isRevealing: context.isRevealing(post.id),
            expireAt: post.burnOnReadExpireAt,
            readDurationMillis: post.burnOnReadReadDurationMillis,
            receipt: isSender ? context.burnOnReadReceipt(post.id) : nil
        )
    }

    static func authorStatus(for post: Post, context: TimelineContext) -> UserStatusValue? {
        guard !post.isSystemMessage, post.overrideUsername == nil, !post.userId.isEmpty else { return nil }
        return context.status(post.userId)
    }

    static func following(for post: Post, context: TimelineContext) -> Bool? {
        guard context.followThreads, !post.isReply, !post.isSystemMessage, !post.isDeleted, post.pendingPostId != post.id else { return nil }
        return context.isFollowing(post.id)
    }

    static func threadSummary(for post: Post, context: TimelineContext) -> ThreadSummary? {
        guard !post.isReply, !post.isDeleted, post.replyCount > 0 else { return nil }
        let participants = post.participantIds.reversed().prefix(ThreadSummary.maxParticipants).map { id in
            ThreadParticipant(id: id, name: context.userName(id), avatarURL: context.userAvatarURL(id))
        }
        let lastReply = post.lastReplyAt > 0 ? "Last reply \(TimeFormatting.relative(post.lastReplyAt.mattermostDate, now: context.now, calendar: context.calendar))" : ""
        let seenAt = max(context.lastViewedAt, context.threadSeenAt(post.id))
        let hasNew = seenAt > 0 && post.lastReplyAt > seenAt && context.openThreadId != post.id
        return ThreadSummary(replyCount: post.replyCount, participants: Array(participants), lastReplyText: lastReply, hasNewReplies: hasNew)
    }

    static func replyContext(for post: Post, previous: Post?, context: TimelineContext) -> ReplyContext? {
        guard post.isReply else { return nil }
        if let previous, previous.threadId == post.rootId { return nil }
        guard let root = context.post(post.rootId) else {
            return ReplyContext(rootId: post.rootId, authorName: "", snippet: "")
        }
        return ReplyContext(rootId: root.id, authorName: context.displayName(root), snippet: snippet(root.message))
    }

    static func snippet(_ message: String, limit: Int = 90) -> String {
        let plain = MessageRenderer.plainText(message)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard plain.count > limit else { return plain }
        return String(plain.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func reactions(for post: Post, context: TimelineContext) -> [ReactionChipModel] {
        post.reactionSummary.map { summary in
            ReactionChipModel(
                emojiName: summary.emojiName,
                glyph: EmojiGlyph.glyph(for: summary.emojiName),
                customEmojiId: context.customEmojiId(summary.emojiName),
                count: summary.count,
                isMine: summary.userIds.contains(context.myId),
                userNames: summary.userIds.map(context.userName)
            )
        }
    }
}

enum MentionDetector {
    static let broadcastKeys = ["@channel", "@all", "@here"]

    static func mentions(_ message: String, username: String, keys: [String]) -> Bool {
        guard !message.isEmpty else { return false }
        let lowered = message.lowercased()
        var candidates = broadcastKeys
        if !username.isEmpty { candidates.append("@" + username.lowercased()) }
        for key in keys {
            let trimmed = key.trimmingCharacters(in: .whitespaces).lowercased()
            if !trimmed.isEmpty { candidates.append(trimmed) }
        }
        return candidates.contains { containsWord($0, in: lowered) }
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex || !isWordCharacter(text[range.upperBound])
            if beforeOK && afterOK { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "@"
    }
}

enum EmojiGlyph {
    static let frequent: [(name: String, glyph: String)] = [
        ("+1", "👍"), ("heart", "❤️"), ("joy", "😂"), ("smile", "😄"), ("tada", "🎉"), ("eyes", "👀"),
        ("white_check_mark", "✅"), ("pray", "🙏"), ("fire", "🔥"), ("rocket", "🚀"), ("thinking_face", "🤔"),
        ("100", "💯"), ("-1", "👎"), ("clap", "👏"), ("wave", "👋"), ("slightly_smiling_face", "🙂"),
    ]

    static let aliases: [String: String] = ["thumbsup": "👍", "thumbsdown": "👎", "laughing": "😆", "ok_hand": "👌"]

    static func glyph(for name: String) -> String? {
        if let glyph = Emoji.unicode(for: name) { return glyph }
        if let match = frequent.first(where: { $0.name == name }) { return match.glyph }
        return aliases[name]
    }
}
