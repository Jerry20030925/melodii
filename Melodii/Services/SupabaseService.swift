//
//  SupabaseService.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import Supabase
import Combine

@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private let client = SupabaseConfig.client

    private init() {}

    // MARK: - Users

    /// 获取指定 ID 的用户
    func fetchUser(id: String) async throws -> User {
        let user: User = try await client
            .from("users")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return user
    }

    /// 按昵称或 MID 搜索用户
    func searchUsers(keyword: String, limit: Int = 50) async throws -> [User] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }

        let users: [User] = try await client
            .from("users")
            .select()
            .or("nickname.ilike.%\(kw)%,mid.ilike.%\(kw)%")
            .order("updated_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return users
    }

    /// 更新用户资料（任意字段可选）
    func updateUser(
        id: String,
        nickname: String?,
        bio: String?,
        avatarURL: String?,
        coverURL: String?
    ) async throws {
        struct Patch: Encodable {
            let nickname: String?
            let bio: String?
            let avatar_url: String?
            let cover_image_url: String?
            let updated_at: String
        }

        let payload = Patch(
            nickname: nickname,
            bio: bio,
            avatar_url: avatarURL,
            cover_image_url: coverURL,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await client
            .from("users")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// 更新用户引导信息（生日、兴趣、完成状态）
    func updateUserOnboarding(
        userId: String,
        birthday: Date,
        interests: [String]
    ) async throws {
        struct Patch: Encodable {
            let birthday: Date
            let interests: [String]
            let is_onboarding_completed: Bool
            let updated_at: String
        }

        let payload = Patch(
            birthday: birthday,
            interests: interests,
            is_onboarding_completed: true,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    /// 是否已关注
    func isFollowing(followerId: String, followingId: String) async throws -> Bool {
        let rows: [Follow] = try await client
            .from("follows")
            .select("id")
            .eq("follower_id", value: followerId)
            .eq("following_id", value: followingId)
            .limit(1)
            .execute()
            .value

        return !rows.isEmpty
    }

    /// 关注用户（若已存在则忽略）
    func followUser(followerId: String, followingId: String) async throws {
        struct InsertFollow: Encodable {
            let follower_id: String
            let following_id: String
        }

        do {
            _ = try await client
                .from("follows")
                .insert(InsertFollow(follower_id: followerId, following_id: followingId))
                .execute()
        } catch {
            let errStr = String(describing: error).lowercased()
            if errStr.contains("duplicate") || errStr.contains("unique") {
                return
            }
            throw error
        }
    }

    /// 取消关注
    func unfollowUser(followerId: String, followingId: String) async throws {
        _ = try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: followerId)
            .eq("following_id", value: followingId)
            .execute()
    }

    // MARK: - Posts

    /// 获取单个帖子
    func fetchPost(id: String) async throws -> Post {
        let post: Post = try await client
            .from("posts")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return post
    }

    /// 获取用户的已发布帖子（按时间倒序）
    func fetchUserPosts(userId: String) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("author_id", value: userId)
            .eq("status", value: PostStatus.published.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
        return posts
    }

    /// 删除帖子（标记为 deleted 或直接删除）
    func deletePost(id: String) async throws {
        // 这里直接删除记录；如果你想软删除，可以改为 update status = deleted
        _ = try await client
            .from("posts")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// 隐藏帖子（此处用设置为 deleted 代替，因为模型没有 hidden）
    func hidePost(id: String) async throws {
        struct Patch: Encodable { let status: String; let updated_at: String }
        let payload = Patch(status: PostStatus.deleted.rawValue, updated_at: ISO8601DateFormatter().string(from: Date()))
        _ = try await client
            .from("posts")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// 获取草稿
    func fetchDraftPosts(userId: String) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("author_id", value: userId)
            .eq("status", value: PostStatus.draft.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
        return posts
    }

    /// 草稿发布（将 status 置为 published）
    func publishPost(id: String) async throws {
        struct Patch: Encodable { let status: String; let updated_at: String }
        let payload = Patch(status: PostStatus.published.rawValue, updated_at: ISO8601DateFormatter().string(from: Date()))
        _ = try await client
            .from("posts")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// 推荐流（示例：排除自己，按时间倒序；可根据业务替换排序/逻辑）
    func fetchRecommendedPosts(userId: String, limit: Int, offset: Int) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("status", value: PostStatus.published.rawValue)
            .neq("author_id", value: userId)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return posts
    }

    /// 热门流（示例：按 like_count 降序）
    func fetchTrendingPosts(limit: Int, offset: Int) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("status", value: PostStatus.published.rawValue)
            .order("like_count", ascending: false)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return posts
    }

    /// 关注流（取我关注的人发布的帖子）
    func fetchFollowingPosts(userId: String, limit: Int, offset: Int) async throws -> [Post] {
        // 先取我关注的人
        struct Row: Decodable { let following_id: String }
        let following: [Row] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userId)
            .execute()
            .value
        let ids = following.map { $0.following_id }
        if ids.isEmpty { return [] }

        let posts: [Post] = try await client
            .from("posts")
            .select()
            .in("author_id", values: ids)
            .eq("status", value: PostStatus.published.rawValue)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return posts
    }

    /// 搜索帖子（按文本、话题匹配；示例实现）
    func searchPosts(keyword: String, limit: Int, offset: Int) async throws -> [Post] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }

        // 简化：在 text 或 topics 上 ilike
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("status", value: PostStatus.published.rawValue)
            .or("text.ilike.%\(kw)%,topics.ilike.%\(kw)%")
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return posts
    }

    // MARK: - Likes

    func hasLikedPost(userId: String, postId: String) async throws -> Bool {
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("likes")
            .select("id")
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func likePost(userId: String, postId: String) async throws {
        struct Payload: Encodable { let user_id: String; let post_id: String }
        do {
            _ = try await client
                .from("likes")
                .insert(Payload(user_id: userId, post_id: postId))
                .execute()
        } catch {
            let s = String(describing: error).lowercased()
            if s.contains("duplicate") || s.contains("unique") { return }
            throw error
        }
        // 可选：增加 posts.like_count
        _ = try? await client
            .rpc("increment_post_like_count", params: ["post_id": postId])
            .execute()
    }

    func unlikePost(userId: String, postId: String) async throws {
        _ = try await client
            .from("likes")
            .delete()
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .execute()
        // 可选：减少 posts.collect_count
        _ = try? await client
            .rpc("decrement_post_collect_count", params: ["post_id": postId])
            .execute()
    }

    // MARK: - Collections

    func hasCollectedPost(userId: String, postId: String) async throws -> Bool {
        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("collections")
            .select("id")
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func collectPost(userId: String, postId: String) async throws {
        struct Payload: Encodable { let user_id: String; let post_id: String }
        do {
            _ = try await client
                .from("collections")
                .insert(Payload(user_id: userId, post_id: postId))
                .execute()
        } catch {
            let s = String(describing: error).lowercased()
            if s.contains("duplicate") || s.contains("unique") { return }
            throw error
        }
        // 可选：增加 posts.collect_count
        _ = try? await client
            .rpc("increment_post_collect_count", params: ["post_id": postId])
            .execute()
    }

    func uncollectPost(userId: String, postId: String) async throws {
        _ = try await client
            .from("collections")
            .delete()
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .execute()
        // 可选：减少 posts.collect_count
        _ = try? await client
            .rpc("decrement_post_collect_count", params: ["post_id": postId])
            .execute()
    }

    /// 获取用户收藏的帖子（简单做法：先查集合，再 in 取帖子）
    func fetchUserCollections(userId: String) async throws -> [Post] {
        struct Row: Decodable { let post_id: String }
        let rows: [Row] = try await client
            .from("collections")
            .select("post_id")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        let ids = rows.map { $0.post_id }
        if ids.isEmpty { return [] }

        let posts: [Post] = try await client
            .from("posts")
            .select()
            .in("id", values: ids)
            .execute()
            .value
        return posts
    }

    // MARK: - Comments

    func fetchComments(postId: String) async throws -> [Comment] {
        let comments: [Comment] = try await client
            .from("comments")
            .select()
            .eq("post_id", value: postId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return comments
    }

    func createComment(postId: String, authorId: String, text: String, replyToId: String?) async throws -> Comment {
        struct Payload: Encodable {
            let post_id: String
            let author_id: String
            let text: String
            let reply_to_id: String?
            let created_at: String
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = Payload(post_id: postId, author_id: authorId, text: text, reply_to_id: replyToId, created_at: now, updated_at: now)

        let inserted: Comment = try await client
            .from("comments")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    // MARK: - Posts Create/Update (CreateView)

    func createPost(
        authorId: String,
        text: String?,
        mediaURLs: [String],
        topics: [String],
        moodTags: [String],
        city: String?,
        isAnonymous: Bool
    ) async throws -> Post {
        struct Payload: Encodable {
            let id: String
            let author_id: String
            let text: String?
            let media_urls: [String]
            let topics: [String]
            let mood_tags: [String]
            let city: String?
            let is_anonymous: Bool
            let like_count: Int
            let comment_count: Int
            let collect_count: Int
            let status: String
            let created_at: String
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        let payload = Payload(
            id: id,
            author_id: authorId,
            text: text,
            media_urls: mediaURLs,
            topics: topics,
            mood_tags: moodTags,
            city: city,
            is_anonymous: isAnonymous,
            like_count: 0,
            comment_count: 0,
            collect_count: 0,
            status: PostStatus.published.rawValue,
            created_at: now,
            updated_at: now
        )

        let post: Post = try await client
            .from("posts")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return post
    }

    func updatePostFull(
        id: String,
        text: String?,
        topics: [String],
        moodTags: [String],
        city: String?,
        isAnonymous: Bool,
        mediaURLs: [String],
        status: PostStatus
    ) async throws {
        struct Patch: Encodable {
            let text: String?
            let topics: [String]
            let mood_tags: [String]
            let city: String?
            let is_anonymous: Bool
            let media_urls: [String]
            let status: String
            let updated_at: String
        }
        let payload = Patch(
            text: text,
            topics: topics,
            mood_tags: moodTags,
            city: city,
            is_anonymous: isAnonymous,
            media_urls: mediaURLs,
            status: status.rawValue,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await client
            .from("posts")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Notifications

    func fetchNotifications(userId: String) async throws -> [Notification] {
        let notifications: [Notification] = try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return notifications
    }

    func markNotificationAsRead(id: String) async throws {
        struct UpdateRead: Encodable {
            let is_read: Bool
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("notifications")
            .update(UpdateRead(is_read: true, updated_at: now))
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Unread Counts

    func fetchUnreadNotificationCount(userId: String) async throws -> Int {
        if let response = try? await client
            .from("notifications")
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute(),
           let exact = response.count {
            return exact
        }

        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("notifications")
            .select("id")
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
            .value
        return rows.count
    }

    func getUnreadMessageCount(userId: String) async throws -> Int {
        if let response = try? await client
            .from("messages")
            .select("*", head: true, count: .exact)
            .eq("receiver_id", value: userId)
            .eq("is_read", value: false)
            .execute(),
           let exact = response.count {
            return exact
        }

        struct Row: Decodable { let id: String }
        let rows: [Row] = try await client
            .from("messages")
            .select("id")
            .eq("receiver_id", value: userId)
            .eq("is_read", value: false)
            .execute()
            .value
        return rows.count
    }

    // MARK: - Conversations

    func getOrCreateConversation(user1Id: String, user2Id: String) async throws -> String {
        // 规范化参与者顺序：小的作为 participant1_id，大的作为 participant2_id
        let p1 = min(user1Id, user2Id)
        let p2 = max(user1Id, user2Id)

        // 直接按 AND 匹配两个字段，唯一确定会话
        struct Row: Decodable { let id: String }
        let exist: [Row] = try await client
            .from("conversations")
            .select("id")
            .eq("participant1_id", value: p1)
            .eq("participant2_id", value: p2)
            .limit(1)
            .execute()
            .value
        if let first = exist.first { return first.id }

        // 不存在则创建
        struct Insert: Encodable {
            let id: String
            let participant1_id: String
            let participant2_id: String
            let last_message_at: String
            let created_at: String
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        let payload = Insert(
            id: id,
            participant1_id: p1,
            participant2_id: p2,
            last_message_at: now,
            created_at: now,
            updated_at: now
        )
        _ = try await client
            .from("conversations")
            .insert(payload)
            .execute()
        return id
    }

    /// 获取单个会话
    func fetchConversation(id: String, currentUserId: String) async throws -> Conversation {
        let conv: Conversation = try await client
            .from("conversations")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return conv
    }

    /// 获取用户的会话列表（已实现）
    func fetchConversations(userId: String) async throws -> [Conversation] {
        let rawConversations: [Conversation] = try await client
            .from("conversations")
            .select()
            .or("participant1_id.eq.\(userId),participant2_id.eq.\(userId)")
            .order("last_message_at", ascending: false)
            .execute()
            .value

        if rawConversations.isEmpty { return [] }

        var userIds = Set<String>()
        for c in rawConversations {
            userIds.insert(c.participant1Id)
            userIds.insert(c.participant2Id)
        }

        let users: [User] = try await client
            .from("users")
            .select()
            .in("id", values: Array(userIds))
            .execute()
            .value
        let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })

        let convIds = rawConversations.map { $0.id }
        let allLatestMessages: [Message] = try await client
            .from("messages")
            .select()
            .in("conversation_id", values: convIds)
            .order("created_at", ascending: false)
            .execute()
            .value

        var lastMessageByConv: [String: Message] = [:]
        for msg in allLatestMessages {
            if lastMessageByConv[msg.conversationId] == nil {
                lastMessageByConv[msg.conversationId] = msg
            }
        }

        let enriched: [Conversation] = rawConversations.map { c in
            var conv = c
            conv.participant1 = userMap[c.participant1Id]
            conv.participant2 = userMap[c.participant2Id]
            conv.lastMessage = lastMessageByConv[c.id]
            return conv
        }

        return enriched
    }

    // MARK: - Messages

    func fetchMessages(conversationId: String, limit: Int, offset: Int) async throws -> [Message] {
        let messages: [Message] = try await client
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId)
            .order("created_at", ascending: true)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return messages
    }

    func sendMessage(conversationId: String, senderId: String, receiverId: String, content: String, messageType: MessageType) async throws -> Message {
        struct InsertMessage: Encodable {
            let conversation_id: String
            let sender_id: String
            let receiver_id: String
            let content: String
            let message_type: String
            let is_read: Bool
            let created_at: String
            let updated_at: String
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let payload = InsertMessage(
            conversation_id: conversationId,
            sender_id: senderId,
            receiver_id: receiverId,
            content: content,
            message_type: messageType.rawValue,
            is_read: false,
            created_at: now,
            updated_at: now
        )

        let inserted: Message = try await client
            .from("messages")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        struct UpdateConversation: Encodable { let last_message_at: String }
        _ = try? await client
            .from("conversations")
            .update(UpdateConversation(last_message_at: now))
            .eq("id", value: conversationId)
            .execute()

        return inserted
    }

    func markMessageAsRead(messageId: String) async throws {
        struct UpdateRead: Encodable {
            let is_read: Bool
            let updated_at: String
        }
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("messages")
            .update(UpdateRead(is_read: true, updated_at: now))
            .eq("id", value: messageId)
            .execute()
    }

    // MARK: - Storage

    /// 聊天/通用媒体上传（已存在）
    func uploadChatMedia(
        data: Data,
        mime: String,
        fileName: String? = nil,
        folder: String,
        bucket: String = "media",
        isPublic: Bool = true
    ) async throws -> String {
        return try await uploadPostMedia(
            data: data,
            mime: mime,
            fileName: fileName,
            folder: folder,
            bucket: bucket,
            isPublic: isPublic
        )
    }

    /// 用户资料媒体上传（转发到 uploadPostMedia）
    func uploadUserMedia(
        data: Data,
        mime: String,
        fileName: String? = nil,
        folder: String,
        bucket: String = "media",
        isPublic: Bool = true
    ) async throws -> String {
        return try await uploadPostMedia(
            data: data,
            mime: mime,
            fileName: fileName,
            folder: folder,
            bucket: bucket,
            isPublic: isPublic
        )
    }

    // 帖子媒体上传（已存在）
    func uploadPostMedia(
        data: Data,
        mime: String,
        fileName: String? = nil,
        folder: String,
        bucket: String = "media",
        isPublic: Bool = true
    ) async throws -> String {
        let name = fileName ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let sanitizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = "\(sanitizedFolder)/\(name)"

        try await client.storage.from(bucket).upload(
            path,
            data: data,
            options: .init(contentType: mime, upsert: true)
        )

        if isPublic {
            let url: URL = try client.storage.from(bucket).getPublicURL(path: path)
            return url.absoluteString
        } else {
            let signedURL: URL = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 60 * 60 * 24)
            return signedURL.absoluteString
        }
    }
}
