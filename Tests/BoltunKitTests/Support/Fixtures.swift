import Foundation
@testable import BoltunKit

enum Fixtures {
    static func json(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        try MattermostJSON.decoder.decode(T.self, from: Data(json(value).utf8))
    }

    static func user(_ id: String, _ username: String, first: String = "", last: String = "", nickname: String = "", roles: String = "system_user", desktop: String = "mention") -> [String: Any] {
        [
            "id": id,
            "create_at": 1_700_000_000_000,
            "update_at": 1_700_000_000_000,
            "delete_at": 0,
            "username": username,
            "auth_service": "",
            "email": "\(username)@example.com",
            "nickname": nickname,
            "first_name": first,
            "last_name": last,
            "position": "",
            "roles": roles,
            "notify_props": [
                "channel": "true",
                "comments": "never",
                "desktop": desktop,
                "desktop_sound": "true",
                "email": "true",
                "first_name": "false",
                "mention_keys": "",
                "push": "mention",
            ],
            "last_password_update": 1_700_000_000_000,
            "locale": "en",
            "timezone": ["automaticTimezone": "", "manualTimezone": "", "useAutomaticTimezone": "true"],
            "disable_welcome_email": false,
        ]
    }

    static func team(_ id: String, _ name: String, display: String, deleteAt: Int64 = 0) -> [String: Any] {
        [
            "id": id,
            "create_at": 1_700_000_000_000,
            "update_at": 1_700_000_000_000,
            "delete_at": deleteAt,
            "display_name": display,
            "name": name,
            "description": "",
            "email": "",
            "type": "O",
            "company_name": "",
            "allowed_domains": "",
            "invite_id": "invite",
            "allow_open_invite": true,
            "scheme_id": NSNull(),
            "group_constrained": NSNull(),
            "policy_id": NSNull(),
        ]
    }

    static func channel(
        _ id: String,
        team: String,
        type: String = "O",
        name: String,
        display: String = "",
        total: Int = 0,
        totalRoot: Int? = nil,
        lastPostAt: Int64 = 0,
        deleteAt: Int64 = 0
    ) -> [String: Any] {
        [
            "id": id,
            "create_at": 1_700_000_000_000,
            "update_at": 1_700_000_000_000,
            "delete_at": deleteAt,
            "team_id": team,
            "type": type,
            "display_name": display,
            "name": name,
            "header": "",
            "purpose": "",
            "last_post_at": lastPostAt,
            "total_msg_count": total,
            "extra_update_at": 0,
            "creator_id": "",
            "scheme_id": NSNull(),
            "props": NSNull(),
            "group_constrained": NSNull(),
            "shared": false,
            "total_msg_count_root": totalRoot ?? total,
            "policy_id": NSNull(),
            "last_root_post_at": lastPostAt,
        ]
    }

    static func member(
        _ channelId: String,
        user: String,
        msgCount: Int = 0,
        mentions: Int = 0,
        lastViewedAt: Int64 = 0,
        markUnread: String = "all",
        desktop: String = "default"
    ) -> [String: Any] {
        [
            "channel_id": channelId,
            "user_id": user,
            "roles": "channel_user",
            "msg_count": msgCount,
            "mention_count": mentions,
            "mention_count_root": mentions,
            "urgent_mention_count": 0,
            "msg_count_root": msgCount,
            "notify_props": [
                "channel_auto_follow_threads": "off",
                "desktop": desktop,
                "email": "default",
                "ignore_channel_mentions": "default",
                "mark_unread": markUnread,
                "push": "default",
            ],
            "scheme_guest": false,
            "scheme_user": true,
            "scheme_admin": false,
            "explicit_roles": "",
            "last_viewed_at": lastViewedAt,
            "last_update_at": 1_700_000_000_000,
        ]
    }

    static func category(_ id: String, user: String, team: String, type: String, display: String, sorting: String = "", channels: [String], collapsed: Bool = false) -> [String: Any] {
        [
            "id": id,
            "user_id": user,
            "team_id": team,
            "sort_order": 0,
            "sorting": sorting,
            "type": type,
            "display_name": display,
            "muted": false,
            "collapsed": collapsed,
            "channel_ids": channels,
        ]
    }

    static func categories(_ list: [[String: Any]]) -> [String: Any] {
        ["categories": list, "order": list.compactMap { $0["id"] as? String }]
    }

    static func post(
        _ id: String,
        channel: String,
        user: String,
        message: String,
        createAt: Int64,
        updateAt: Int64? = nil,
        rootId: String = "",
        type: String = "",
        deleteAt: Int64 = 0,
        pendingPostId: String = "",
        replyCount: Int = 0,
        reactions: [[String: Any]] = [],
        props: [String: Any] = [:]
    ) -> [String: Any] {
        var metadata: [String: Any] = [:]
        if !reactions.isEmpty { metadata["reactions"] = reactions }
        return [
            "id": id,
            "create_at": createAt,
            "update_at": updateAt ?? createAt,
            "edit_at": 0,
            "delete_at": deleteAt,
            "is_pinned": false,
            "user_id": user,
            "channel_id": channel,
            "root_id": rootId,
            "original_id": "",
            "message": message,
            "type": type,
            "props": props,
            "hashtags": "",
            "file_ids": [],
            "pending_post_id": pendingPostId,
            "reply_count": replyCount,
            "last_reply_at": 0,
            "participants": NSNull(),
            "metadata": metadata,
        ]
    }

    static func reaction(user: String, post: String, emoji: String, at: Int64 = 1) -> [String: Any] {
        ["user_id": user, "post_id": post, "emoji_name": emoji, "create_at": at, "update_at": at, "delete_at": 0, "remote_id": "", "channel_id": ""]
    }

    static func postList(_ posts: [[String: Any]], hasNext: Bool = false) -> [String: Any] {
        let sorted = posts.sorted { ($0["create_at"] as! Int64) > ($1["create_at"] as! Int64) }
        return [
            "order": sorted.map { $0["id"] as! String },
            "posts": Dictionary(uniqueKeysWithValues: sorted.map { ($0["id"] as! String, $0) }),
            "next_post_id": "",
            "prev_post_id": "",
            "has_next": hasNext,
            "first_inaccessible_post_time": 0,
        ]
    }

    static func event(_ name: String, data: [String: Any] = [:], channel: String = "", team: String = "", user: String = "", seq: Int64 = 1) -> [String: Any] {
        [
            "event": name,
            "data": data,
            "broadcast": [
                "omit_users": NSNull(),
                "user_id": user,
                "channel_id": channel,
                "team_id": team,
                "connection_id": "",
                "omit_connection_id": "",
            ],
            "seq": seq,
        ]
    }

    static func wsEvent(_ name: String, data: [String: Any] = [:], channel: String = "", team: String = "", user: String = "", seq: Int64 = 1) -> WebSocketEvent {
        WebSocketEvent.parse(json(event(name, data: data, channel: channel, team: team, user: user, seq: seq)))!
    }

    static func posted(
        _ post: [String: Any],
        channelType: String = "O",
        channelDisplayName: String = "Town Square",
        sender: String = "@bob",
        team: String = "t1",
        mentions: [String]? = nil,
        seq: Int64 = 1
    ) -> WebSocketEvent {
        var data: [String: Any] = [
            "channel_display_name": channelDisplayName,
            "channel_name": "town-square",
            "channel_type": channelType,
            "post": json(post),
            "sender_name": sender,
            "set_online": true,
            "team_id": team,
        ]
        if let mentions { data["mentions"] = json(mentions) }
        return wsEvent("posted", data: data, channel: post["channel_id"] as! String, seq: seq)
    }

    static func hello(_ connectionId: String, seq: Int64 = 0) -> [String: Any] {
        event("hello", data: ["connection_id": connectionId, "server_version": "12.0.1"], user: "me1", seq: seq)
    }

    static var clientConfig: [String: Any] { [
        "SiteName": "Example Chat",
        "Version": "12.0.1",
        "MaxPostSize": "16383",
        "EnableCustomEmoji": "true",
        "CollapsedThreads": "always_on",
        "TeammateNameDisplay": "username",
        "EnableSignInWithUsername": "true",
        "EnableSignInWithEmail": "true",
    ] }
}
