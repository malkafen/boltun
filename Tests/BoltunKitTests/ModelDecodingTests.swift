import Foundation
import Testing
@testable import BoltunKit

@Suite struct PostDecodingTests {
    @Test func decodesRealisticPost() throws {
        let json = """
        {"id":"pifnqw9xy3fste7pis4414i79h","create_at":1792822915504,"update_at":1792822915600,"edit_at":1792822915600,"delete_at":0,
        "is_pinned":true,"user_id":"u1","channel_id":"c1","root_id":"","original_id":"","message":"hello :smile:","type":"",
        "props":{"from_webhook":"true","override_username":"ci-bot","attachments":[{"text":"build ok","color":"#00ff00"}]},
        "hashtags":"#tag","file_ids":["f1"],"pending_post_id":"u1:1792822915000","reply_count":3,"last_reply_at":1792822916000,
        "participants":null,
        "metadata":{"files":[{"id":"f1","post_id":"pifnqw9xy3fste7pis4414i79h","name":"shot.PNG","extension":"PNG","size":"2048","mime_type":"","width":640,"height":480.0,"has_preview_image":true}],
        "reactions":[{"user_id":"u2","post_id":"pifnqw9xy3fste7pis4414i79h","emoji_name":"+1","create_at":20},{"user_id":"u3","post_id":"pifnqw9xy3fste7pis4414i79h","emoji_name":"smile","create_at":10},{"user_id":"u4","post_id":"pifnqw9xy3fste7pis4414i79h","emoji_name":"+1","create_at":30}],
        "emojis":[{"id":"e1","name":"parrot","creator_id":"u9"}],
        "embeds":[{"type":"opengraph","url":"https://example.com","data":{"title":"x"}}]}}
        """
        let post = try MattermostJSON.decoder.decode(Post.self, from: Data(json.utf8))
        #expect(post.id == "pifnqw9xy3fste7pis4414i79h")
        #expect(post.createAt == 1792822915504)
        #expect(post.isEdited)
        #expect(!post.isDeleted)
        #expect(post.isPinned)
        #expect(post.hashtags == "#tag")
        #expect(post.fileIds == ["f1"])
        #expect(post.pendingPostId == "u1:1792822915000")
        #expect(post.replyCount == 3)
        #expect(post.lastReplyAt == 1792822916000)
        #expect(post.overrideUsername == "ci-bot")
        #expect(post.attachments.count == 1)
        #expect(post.attachments.first?["text"]?.stringValue == "build ok")
        let file = try #require(post.metadata.files.first)
        #expect(file.size == 2048)
        #expect(file.height == 480)
        #expect(file.isImage)
        #expect(file.hasPreviewImage)
        #expect(post.metadata.emojis.first?.name == "parrot")
        #expect(post.metadata.emojis.first?.creatorId == "u9")
        #expect(post.metadata.embeds.first == PostEmbed(type: "opengraph", url: "https://example.com"))
        #expect(post.reactionSummary == [
            ReactionSummary(emojiName: "smile", userIds: ["u3"]),
            ReactionSummary(emojiName: "+1", userIds: ["u2", "u4"]),
        ])
        #expect(post.reactionSummary.last?.count == 2)
    }

    @Test func toleratesMissingAndMistypedFields() throws {
        let post = try Fixtures.decode(Post.self, [
            "id": "p1",
            "create_at": "1700000000000",
            "update_at": 1.7e12,
            "delete_at": "not a number",
            "reply_count": "4",
            "metadata": [:],
            "props": "unexpected",
            "file_ids": NSNull(),
        ])
        #expect(post.createAt == 1_700_000_000_000)
        #expect(post.updateAt == 1_700_000_000_000)
        #expect(post.deleteAt == 0)
        #expect(post.replyCount == 4)
        #expect(post.userId == "")
        #expect(post.message == "")
        #expect(post.props.isEmpty)
        #expect(post.fileIds.isEmpty)
        #expect(post.metadata == PostMetadata())
    }

    @Test func requiresId() {
        #expect(throws: DecodingError.self) { try Fixtures.decode(Post.self, ["message": "x"]) }
    }

    @Test func derivedProperties() {
        let root = Post(id: "r", userId: "u", channelId: "c", message: "m")
        let reply = Post(id: "x", deleteAt: 5, userId: "u", channelId: "c", rootId: "r", message: "", type: "system_join_channel")
        #expect(!root.isReply)
        #expect(root.threadId == "r")
        #expect(reply.isReply)
        #expect(reply.threadId == "r")
        #expect(reply.isSystemMessage)
        #expect(reply.isDeleted)
        #expect(!root.isEdited)
        #expect(root.overrideUsername == nil)
        let bot = Post(id: "b", userId: "u", channelId: "c", message: "", props: ["from_bot": .bool(true), "override_username": .string("bot")])
        #expect(bot.overrideUsername == "bot")
        let spoof = Post(id: "s", userId: "u", channelId: "c", message: "", props: ["override_username": .string("admin")])
        #expect(spoof.overrideUsername == nil)
        #expect(root.attachments.isEmpty)
    }

    @Test func roundTripsThroughEncoder() throws {
        let post = Post(
            id: "p",
            createAt: 1,
            updateAt: 2,
            editAt: 3,
            deleteAt: 0,
            isPinned: true,
            userId: "u",
            channelId: "c",
            rootId: "r",
            message: "hi",
            type: "",
            props: ["a": .number(1)],
            hashtags: "#x",
            fileIds: ["f"],
            pendingPostId: "pp",
            replyCount: 2,
            lastReplyAt: 9,
            metadata: PostMetadata(
                files: [FileInfo(id: "f", postId: "p", name: "a.txt", extension: "txt", size: 1, mimeType: "text/plain", width: 0, height: 0, hasPreviewImage: false)],
                reactions: [Reaction(userId: "u", postId: "p", emojiName: "smile", createAt: 4)],
                emojis: [CustomEmoji(id: "e", name: "parrot", creatorId: "u")],
                embeds: [PostEmbed(type: "image", url: "https://x")]
            )
        )
        let data = try MattermostJSON.encoder.encode(post)
        #expect(try MattermostJSON.decoder.decode(Post.self, from: data) == post)
    }

    @Test func fileInfoImageDetection() {
        #expect(FileInfo(id: "1", name: "a", mimeType: "image/png").isImage)
        #expect(FileInfo(id: "2", name: "a.JPEG", extension: "JPEG").isImage)
        #expect(!FileInfo(id: "3", name: "a.pdf", extension: "pdf", mimeType: "application/pdf").isImage)
    }

    @Test func fileInfoAndEmojiRequireIds() {
        #expect(throws: DecodingError.self) { try Fixtures.decode(FileInfo.self, ["name": "x"]) }
        #expect(throws: DecodingError.self) { try Fixtures.decode(CustomEmoji.self, ["name": "x"]) }
        let reaction = try? Fixtures.decode(Reaction.self, [:])
        #expect(reaction == Reaction(userId: "", postId: "", emojiName: ""))
    }

    @Test func postListOrdersPostsAndSkipsMissing() throws {
        let list = try Fixtures.decode(PostList.self, [
            "order": ["b", "a", "missing"],
            "posts": [
                "a": Fixtures.post("a", channel: "c", user: "u", message: "first", createAt: 1),
                "b": Fixtures.post("b", channel: "c", user: "u", message: "second", createAt: 2),
            ],
            "next_post_id": "n",
            "prev_post_id": "p",
            "has_next": true,
        ])
        #expect(list.orderedPosts.map(\.id) == ["b", "a"])
        #expect(list.nextPostId == "n")
        #expect(list.prevPostId == "p")
        #expect(list.hasNext)
        let empty = try Fixtures.decode(PostList.self, ["order": NSNull()])
        #expect(empty == PostList())
    }

    @Test func searchResultsDecode() throws {
        let results = try Fixtures.decode(PostSearchResults.self, [
            "order": ["a"],
            "posts": ["a": Fixtures.post("a", channel: "c", user: "u", message: "found", createAt: 1)],
            "matches": ["a": ["found"]],
            "has_next": true,
        ])
        #expect(results.orderedPosts.map(\.message) == ["found"])
        #expect(results.hasNext)
        #expect(try Fixtures.decode(PostSearchResults.self, [:]) == PostSearchResults())
    }
}

@Suite struct ChannelDecodingTests {
    @Test func decodesLiveChannel() throws {
        let channel = try Fixtures.decode(Channel.self, Fixtures.channel("c1", team: "", type: "D", name: "a__b", total: 7, totalRoot: 5, lastPostAt: 42))
        #expect(channel.type == .direct)
        #expect(channel.type.isDirectOrGroup)
        #expect(channel.totalMsgCount == 7)
        #expect(channel.totalMsgCountRoot == 5)
        #expect(channel.lastPostAt == 42)
        #expect(channel.lastRootPostAt == 42)
        #expect(!channel.isArchived)
    }

    @Test func unknownTypeFallsBackToOpen() throws {
        let channel = try Fixtures.decode(Channel.self, ["id": "c", "type": "X", "total_msg_count": "12", "delete_at": 9])
        #expect(channel.type == .open)
        #expect(channel.totalMsgCount == 12)
        #expect(channel.isArchived)
        #expect(!ChannelType.private.isDirectOrGroup)
        #expect(ChannelType.group.isDirectOrGroup)
    }

    @Test func directPartner() {
        let direct = Channel(id: "d", type: .direct, name: "me__you")
        #expect(direct.directPartnerId(me: "me") == "you")
        #expect(direct.directPartnerId(me: "you") == "me")
        #expect(Channel(id: "s", type: .direct, name: "me__me").directPartnerId(me: "me") == "me")
        #expect(Channel(id: "m", type: .direct, name: "broken").directPartnerId(me: "me") == nil)
        #expect(Channel(id: "o", type: .open, name: "me__you").directPartnerId(me: "me") == nil)
    }

    @Test func memberDecodesNotifyPropsWithMixedTypes() throws {
        var raw = Fixtures.member("c", user: "u", msgCount: 3, mentions: 2, lastViewedAt: 77, markUnread: "mention", desktop: "all")
        var props = raw["notify_props"] as! [String: Any]
        props["push_threads"] = true
        props["weird"] = ["nested": 1]
        raw["notify_props"] = props
        raw["urgent_mention_count"] = "1"
        let member = try Fixtures.decode(ChannelMember.self, raw)
        #expect(member.msgCount == 3)
        #expect(member.mentionCount == 2)
        #expect(member.mentionCountRoot == 2)
        #expect(member.urgentMentionCount == 1)
        #expect(member.lastViewedAt == 77)
        #expect(member.isMuted)
        #expect(member.desktopNotifyLevel == "all")
        #expect(member.notifyProps["push_threads"] == "true")
        #expect(member.notifyProps["weird"] == nil)
        let bare = try Fixtures.decode(ChannelMember.self, [:])
        #expect(bare.desktopNotifyLevel == "default")
        #expect(!bare.isMuted)
    }

    @Test func categoriesDecodeServerSortingValues() throws {
        let alpha = try Fixtures.decode(ChannelCategory.self, Fixtures.category("a", user: "u", team: "t", type: "custom", display: "Work", sorting: "alpha", channels: ["x"]))
        #expect(alpha.sorting == .alphabetical)
        #expect(alpha.type == .custom)
        let recent = try Fixtures.decode(ChannelCategory.self, Fixtures.category("r", user: "u", team: "t", type: "direct_messages", display: "DM", sorting: "recent", channels: [], collapsed: true))
        #expect(recent.sorting == .recent)
        #expect(recent.collapsed)
        let manual = try Fixtures.decode(ChannelCategory.self, ["id": "m", "type": "weird", "sorting": "manual"])
        #expect(manual.sorting == .manual)
        #expect(manual.type == .custom)
        let unknown = try Fixtures.decode(ChannelCategory.self, ["id": "u", "sorting": "random"])
        #expect(unknown.sorting == .default)
        let encoded = try JSONSerialization.jsonObject(with: MattermostJSON.encoder.encode(alpha)) as! [String: Any]
        #expect(encoded["sorting"] as? String == "alpha")
        #expect(encoded["channel_ids"] as? [String] == ["x"])
        #expect(encoded["team_id"] as? String == "t")
    }

    @Test func orderedCategoriesFollowOrderThenAppendRest() throws {
        let ordered = try Fixtures.decode(OrderedChannelCategories.self, [
            "categories": [
                Fixtures.category("b", user: "u", team: "t", type: "channels", display: "B", channels: []),
                Fixtures.category("a", user: "u", team: "t", type: "favorites", display: "A", channels: []),
                Fixtures.category("c", user: "u", team: "t", type: "custom", display: "C", channels: []),
            ],
            "order": ["a", "ghost", "b"],
        ])
        #expect(ordered.sorted.map(\.id) == ["a", "b", "c"])
    }

    @Test func channelStats() throws {
        let stats = try Fixtures.decode(ChannelStats.self, ["channel_id": "c", "member_count": 12, "pinnedpost_count": "3", "guest_count": 0])
        #expect(stats == ChannelStats(channelId: "c", memberCount: 12, pinnedPostCount: 3))
    }
}

@Suite struct UserAndTeamDecodingTests {
    @Test func decodesLiveUser() throws {
        let json = """
        {"id":"g3td8kx76tnw7bumbf57h5c6hw","create_at":1792822915245,"update_at":1792823858686,"delete_at":0,"username":"boltun","auth_service":"",
        "email":"boltun@example.com","nickname":"","first_name":"","last_name":"","position":"","roles":"system_user system_admin",
        "notify_props":{"channel":"true","desktop":"mention","desktop_sound":"true","push":"mention"},"last_password_update":1792822915245,
        "locale":"en","timezone":{"automaticTimezone":"","manualTimezone":"","useAutomaticTimezone":"true"},"remote_id":"","disable_welcome_email":false}
        """
        let user = try MattermostJSON.decoder.decode(User.self, from: Data(json.utf8))
        #expect(user.username == "boltun")
        #expect(user.isSystemAdmin)
        #expect(!user.isDeactivated)
        #expect(user.updateAt == 1792823858686)
        #expect(user.notifyProps["desktop"] == "mention")
        #expect(user.timezone["useAutomaticTimezone"] == "true")
        #expect(user.fullName == "")
        #expect(user.displayName(.fullName) == "boltun")
        #expect(user.displayName(.nickname) == "boltun")
    }

    @Test func displayNames() throws {
        let user = try Fixtures.decode(User.self, Fixtures.user("u", "bob", first: "Bob", last: "Builder", nickname: "bobby"))
        #expect(user.displayName() == "bob")
        #expect(user.displayName(.fullName) == "Bob Builder")
        #expect(user.displayName(.nickname) == "bobby")
        let noNick = User(id: "x", username: "x", firstName: "Only")
        #expect(noNick.displayName(.nickname) == "Only")
        #expect(!noNick.isSystemAdmin)
        #expect(User(id: "d", username: "d", deleteAt: 1).isDeactivated)
        let bare = try Fixtures.decode(User.self, ["id": "z", "is_bot": true, "notify_props": NSNull(), "last_picture_update": "55"])
        #expect(bare.isBot)
        #expect(bare.notifyProps.isEmpty)
        #expect(bare.lastPictureUpdate == 55)
    }

    @Test func nameDisplayPreference() {
        #expect(NameDisplaySetting(preference: "full_name") == .fullName)
        #expect(NameDisplaySetting(preference: "nickname_full_name") == .nickname)
        #expect(NameDisplaySetting(preference: "garbage") == .username)
        #expect(NameDisplaySetting(preference: nil) == .username)
    }

    @Test func teamDecodingAndInitials() throws {
        let team = try Fixtures.decode(Team.self, Fixtures.team("t", "dev-team", display: "Core platform"))
        #expect(team.initials == "CP")
        #expect(team.type == "O")
        #expect(Team(id: "a", name: "my_team", displayName: "").initials == "MT")
        #expect(Team(id: "b", name: "x", displayName: "--").initials == "--")
        #expect(Team(id: "c", name: "solo", displayName: "Solo").initials == "S")
        let bare = try Fixtures.decode(Team.self, ["id": "t", "last_team_icon_update": 12])
        #expect(bare.type == "O")
        #expect(bare.lastTeamIconUpdate == 12)
        #expect(throws: DecodingError.self) { try Fixtures.decode(Team.self, ["name": "x"]) }
    }

    @Test func teamMemberAndUnread() throws {
        let member = try Fixtures.decode(TeamMember.self, ["team_id": "t", "user_id": "u", "roles": "team_user team_admin", "delete_at": 0, "scheme_guest": false])
        #expect(member == TeamMember(teamId: "t", userId: "u", roles: "team_user team_admin"))
        let unread = try Fixtures.decode(TeamUnread.self, ["team_id": "t", "msg_count": 4, "mention_count": "2", "msg_count_root": 3, "mention_count_root": 1, "thread_count": 1, "thread_mention_count": 1, "thread_urgent_mention_count": 0])
        #expect(unread == TeamUnread(teamId: "t", msgCount: 4, mentionCount: 2, threadCount: 1, threadMentionCount: 1, msgCountRoot: 3, mentionCountRoot: 1))
    }

    @Test func statusAndPreference() throws {
        let status = try Fixtures.decode(UserStatus.self, ["user_id": "u", "status": "dnd", "manual": true, "last_activity_at": 5, "dnd_end_time": 0])
        #expect(status == UserStatus(userId: "u", status: .dnd, manual: true, lastActivityAt: 5))
        let unknown = try Fixtures.decode(UserStatus.self, ["user_id": "u", "status": "ooo"])
        #expect(unknown.status == .offline)
        let preference = try Fixtures.decode(Preference.self, ["user_id": "u", "category": "display_settings", "name": "name_format", "value": "full_name"])
        #expect(preference == Preference(userId: "u", category: "display_settings", name: "name_format", value: "full_name"))
        #expect(try Fixtures.decode(Preference.self, [:]) == Preference(userId: "", category: "", name: "", value: ""))
    }

    @Test func serverErrorBody() throws {
        let body = try Fixtures.decode(ServerErrorBody.self, ["id": "api.context.session_expired.app_error", "message": "Invalid or expired session", "detail": "", "request_id": "r1", "status_code": 401])
        #expect(body == ServerErrorBody(id: "api.context.session_expired.app_error", message: "Invalid or expired session", statusCode: 401, requestId: "r1"))
    }

    @Test func clientConfigAccessors() {
        let config = ClientConfig(values: [
            "SiteName": "Chat",
            "Version": "12.0.1",
            "MaxPostSize": "4000",
            "EnableSignInWithUsername": "false",
            "EnableSignUpWithGitLab": "true",
            "EnableSignUpWithGoogle": "true",
            "EnableSignUpWithOffice365": "true",
            "EnableSignUpWithOpenId": "true",
            "EnableSaml": "true",
            "EnableCustomEmoji": "true",
            "CollapsedThreads": "always_on",
            "TeammateNameDisplay": "full_name",
        ])
        #expect(config.siteName == "Chat")
        #expect(config.version == "12.0.1")
        #expect(config.maxPostSize == 4000)
        #expect(!config.enableSignInWithUsername)
        #expect(config.enableSignInWithEmail)
        #expect(config.enableGitLab && config.enableGoogle && config.enableOffice365 && config.enableOpenId && config.enableSaml)
        #expect(config.enableCustomEmoji)
        #expect(config.collapsedThreads == "always_on")
        #expect(config.teammateNameDisplay == "full_name")
        #expect(config["Version"] == "12.0.1")
        let empty = ClientConfig(values: ["SiteName": ""])
        #expect(empty.siteName == "Mattermost")
        #expect(empty.maxPostSize == 16383)
        #expect(empty.collapsedThreads == "disabled")
        #expect(empty.teammateNameDisplay == "username")
        #expect(!empty.enableCustomEmoji)
    }

    @Test func millisecondConversions() {
        let date = Int64(1_700_000_000_123).mattermostDate
        #expect(date.timeIntervalSince1970 == 1_700_000_000.123)
        #expect(date.mattermostMillis == 1_700_000_000_123)
    }

    @Test func numericFallbacksClampExtremes() throws {
        let huge = try Fixtures.decode(Channel.self, ["id": "c", "last_post_at": 1e300, "delete_at": -1e300, "total_msg_count": " 7 ", "total_msg_count_root": "2.9"])
        #expect(huge.lastPostAt == .max)
        #expect(huge.deleteAt == .min)
        #expect(huge.totalMsgCount == 7)
        #expect(huge.totalMsgCountRoot == 2)
        #expect(Int64(clamping: Double.nan) == 0)
    }
}

@Suite struct WebSocketEventDecodingTests {
    @Test func parsesPostedEventWithEmbeddedJSONStrings() throws {
        let text = """
        {"event":"posted","data":{"channel_display_name":"Town Square","channel_name":"town-square","channel_type":"O",
        "mentions":"[\\"me1\\"]","post":"{\\"id\\":\\"p1\\",\\"create_at\\":5,\\"user_id\\":\\"u2\\",\\"channel_id\\":\\"c1\\",\\"message\\":\\"hi @alice\\",\\"props\\":{\\"disable_group_highlight\\":true}}",
        "sender_name":"@bob","set_online":true,"team_id":"t1"},
        "broadcast":{"omit_users":null,"user_id":"","channel_id":"c1","team_id":"","connection_id":"","omit_connection_id":""},"seq":7}
        """
        let event = try #require(WebSocketEvent.parse(text))
        #expect(event.event == "posted")
        #expect(event.seq == 7)
        #expect(event.channelId == "c1")
        #expect(event.broadcast.omitUsers.isEmpty)
        let post = try #require(event.embedded(Post.self, "post"))
        #expect(post.message == "hi @alice")
        #expect(post.props["disable_group_highlight"]?.boolValue == true)
        #expect(event.embedded([String].self, "mentions") == ["me1"])
        #expect(event.string("sender_name") == "@bob")
        #expect(event.data["set_online"]?.boolValue == true)
    }

    @Test func embeddedHandlesObjectsArraysAndInvalidValues() {
        let event = WebSocketEvent(event: "x", data: [
            "user": .object(["id": .string("u1"), "username": .string("bob")]),
            "list": .array([.string("a"), .string("b")]),
            "number": .number(1),
            "broken": .string("{not json"),
        ])
        #expect(event.embedded(User.self, "user")?.username == "bob")
        #expect(event.embedded([String].self, "list") == ["a", "b"])
        #expect(event.embedded(User.self, "number") == nil)
        #expect(event.embedded(User.self, "broken") == nil)
        #expect(event.embedded(User.self, "missing") == nil)
    }

    @Test func channelIdFallsBackToData() {
        let event = WebSocketEvent(event: "channel_viewed", data: ["channel_id": .string("c9")])
        #expect(event.channelId == "c9")
        #expect(WebSocketEvent(event: "x").channelId == "")
    }

    @Test func rejectsRepliesAndGarbage() {
        #expect(WebSocketEvent.parse(#"{"status":"OK","seq_reply":1}"#) == nil)
        #expect(WebSocketEvent.parse("not json") == nil)
        #expect(WebSocketEvent.parse(#"{"event":""}"#) == nil)
    }

    @Test func broadcastDecodesOmitUsers() throws {
        let broadcast = try Fixtures.decode(WebSocketBroadcast.self, ["omit_users": ["u1": true], "user_id": "u", "channel_id": "c", "team_id": "t"])
        #expect(broadcast == WebSocketBroadcast(channelId: "c", teamId: "t", userId: "u", omitUsers: ["u1": true]))
    }
}
