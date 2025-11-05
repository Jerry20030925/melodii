//
//  SupabaseService.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import Supabase
import Combine

// MARK: - Top-level DTOs to avoid @MainActor isolation

private struct UsersPatch: Encodable, Sendable {
    let nickname: String?
    let bio: String?
    let avatar_url: String?
    let cover_image_url: String?
    let updated_at: String
}

private struct UsersMIDPatch: Encodable, Sendable {
    let mid: String
    let last_mid_update: String
    let updated_at: String
}

private struct UsersOnboardingPatch: Encodable, Sendable {
    let birthday: Date
    let interests: [String]
    let is_onboarding_completed: Bool
    let updated_at: String
}

private struct FollowInsert: Encodable, Sendable {
    let follower_id: String
    let following_id: String
}

// Explicitly nonisolated to satisfy Encodable & Sendable in generic context
nonisolated private struct MintUserMIDParams: Encodable, Sendable { let uid: String }
// Explicitly nonisolated to satisfy Decodable & Sendable in generic context
nonisolated private struct MintUserMIDRow: Decodable, Sendable { let mint_mid_for_user: String? }

private struct PostStatusPatch: Encodable, Sendable {
    let status: String
    let updated_at: String
}

private struct CollectionInsert: Encodable, Sendable { let user_id: String; let post_id: String }
private struct LikeInsert: Encodable, Sendable { let user_id: String; let post_id: String }

private struct CollectionsRow: Decodable, Sendable { let post_id: String }
private struct LikesRowId: Decodable, Sendable { let id: String }
private struct GenericIdRow: Decodable, Sendable { let id: String }
private struct FollowingRow: Decodable, Sendable { let following_id: String }

private struct CommentInsert: Encodable, Sendable {
    let post_id: String
    let author_id: String
    let text: String
    let reply_to_id: String?
    let created_at: String
    let updated_at: String
}
 
 private struct ReportInsert: Encodable, Sendable {
     let reporter_id: String
     let reported_user_id: String?
     let post_id: String?
     let comment_id: String?
     let reason: String?
     let created_at: String
 }

private struct PostInsert: Encodable, Sendable {
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

private struct PostFullPatch: Encodable, Sendable {
    let text: String?
    let topics: [String]
    let mood_tags: [String]
    let city: String?
    let is_anonymous: Bool
    let media_urls: [String]
    let status: String
    let updated_at: String
}

private struct ConversationInsert: Encodable, Sendable {
    let id: String
    let participant1_id: String
    let participant2_id: String
    let last_message_at: String
    let created_at: String
    let updated_at: String
}

private struct ConversationUpdate: Encodable, Sendable { let last_message_at: String }

private struct MessageInsert: Encodable, Sendable {
    let conversation_id: String
    let sender_id: String
    let receiver_id: String
    let content: String
    let message_type: String
    let is_read: Bool
    let created_at: String
    let updated_at: String
}

private struct MessageReadUpdate: Encodable, Sendable {
    let is_read: Bool
    let updated_at: String
}

private struct NotificationReadUpdate: Encodable, Sendable {
    let is_read: Bool
    let updated_at: String
}

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    private let client = SupabaseConfig.client

    // 用户信息缓存
    private var userCache: [String: (user: User, timestamp: Date)] = [:]
    private let userCacheExpiration: TimeInterval = 300 // 5分钟缓存

    private init() {}

    // MARK: - Users

    /// 获取指定 ID 的用户（带缓存）
    func fetchUser(id: String) async throws -> User {
        // 检查缓存
        if let cached = userCache[id] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < userCacheExpiration {
                print("✅ 从缓存获取用户信息: \(id)")
                return cached.user
            } else {
                // 缓存过期，移除
                userCache.removeValue(forKey: id)
            }
        }

        // 从网络获取
        let user: User = try await client
            .from("users")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        // 保存到缓存
        userCache[id] = (user, Date())
        print("✅ 从网络获取并缓存用户信息: \(id)")

        return user
    }

    /// 清除用户缓存
    func clearUserCache() {
        userCache.removeAll()
        print("✅ 已清除用户缓存")
    }

    /// 清除特定用户的缓存
    func clearUserCache(userId: String) {
        userCache.removeValue(forKey: userId)
        print("✅ 已清除用户 \(userId) 的缓存")
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
        coverURL: String?,
        interests: [String]? = nil
    ) async throws {
        let payload = UsersPatch(
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

        // 如果提供了interests，单独更新（因为UsersPatch可能不包含此字段）
        if let interests = interests {
            struct InterestsUpdate: Encodable {
                let interests: [String]
                let updated_at: String
            }
            let interestsPayload = InterestsUpdate(
                interests: interests,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )

            _ = try await client
                .from("users")
                .update(interestsPayload)
                .eq("id", value: id)
                .execute()
        }
    }

    /// 更新用户MID
    func updateUserMID(userId: String, newMID: String) async throws {
        // 验证MID格式
        let validationResult = MIDValidationResult(input: newMID)
        guard validationResult.isValid else {
            throw NSError(domain: "MIDValidation", code: 400, userInfo: [
                NSLocalizedDescriptionKey: validationResult.errorMessage ?? "MID格式无效"
            ])
        }

        // 检查MID是否已被使用
        let existingUsers: [User] = try await client
            .from("users")
            .select("id")
            .eq("mid", value: newMID)
            .neq("id", value: userId)
            .execute()
            .value

        if !existingUsers.isEmpty {
            throw NSError(domain: "MIDValidation", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "该MID已被其他用户使用"
            ])
        }

        let now = Date()

        // 尝试使用包含 last_mid_update 的payload
        do {
            let payload = UsersMIDPatch(
                mid: newMID,
                last_mid_update: ISO8601DateFormatter().string(from: now),
                updated_at: ISO8601DateFormatter().string(from: now)
            )

            _ = try await client
                .from("users")
                .update(payload)
                .eq("id", value: userId)
                .execute()
        } catch {
            // 如果失败（可能是因为 last_mid_update 列不存在），尝试只更新 mid 字段
            print("⚠️ 使用完整payload失败，尝试简化版本: \(error)")

            struct SimpleMIDPatch: Encodable, Sendable {
                let mid: String
                let updated_at: String
            }

            let simplePayload = SimpleMIDPatch(
                mid: newMID,
                updated_at: ISO8601DateFormatter().string(from: now)
            )

            _ = try await client
                .from("users")
                .update(simplePayload)
                .eq("id", value: userId)
                .execute()
        }
    }
    func updateUserOnboarding(
        userId: String,
        birthday: Date,
        interests: [String]
    ) async throws {
        let payload = UsersOnboardingPatch(
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
        // 仅查询 id 字段，用轻量结构解码，避免字段缺失导致解码失败
        let rows: [GenericIdRow] = try await client
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
        // 先检查是否已经关注
        let alreadyFollowing = try await isFollowing(followerId: followerId, followingId: followingId)
        if alreadyFollowing {
            print("✅ 已经关注过此用户，跳过")
            return
        }

        do {
            // 插入关注记录
            _ = try await client
                .from("follows")
                .insert(FollowInsert(follower_id: followerId, following_id: followingId))
                .execute()

            print("✅ 关注记录插入成功")

            // 更新关注者的 following_count
            try await incrementUserFollowingCount(userId: followerId, delta: 1)
            print("✅ 更新关注者following_count成功")

            // 更新被关注者的 followers_count
            try await incrementUserFollowersCount(userId: followingId, delta: 1)
            print("✅ 更新被关注者followers_count成功")
        } catch {
            print("❌ 关注失败: \(error)")
            let errStr = String(describing: error).lowercased()
            if errStr.contains("duplicate") || errStr.contains("unique") {
                print("⚠️ Duplicate错误，忽略")
                return
            }
            throw error
        }
    }

    /// 取消关注
    func unfollowUser(followerId: String, followingId: String) async throws {
        // 先检查是否真的在关注
        let isCurrentlyFollowing = try await isFollowing(followerId: followerId, followingId: followingId)
        if !isCurrentlyFollowing {
            print("✅ 本来就没有关注此用户，跳过")
            return
        }

        do {
            // 删除关注记录
            _ = try await client
                .from("follows")
                .delete()
                .eq("follower_id", value: followerId)
                .eq("following_id", value: followingId)
                .execute()

            print("✅ 取消关注记录删除成功")

            // 更新关注者的 following_count
            try await incrementUserFollowingCount(userId: followerId, delta: -1)
            print("✅ 更新关注者following_count成功")

            // 更新被关注者的 followers_count
            try await incrementUserFollowersCount(userId: followingId, delta: -1)
            print("✅ 更新被关注者followers_count成功")
        } catch {
            print("❌ 取消关注失败: \(error)")
            throw error
        }
    }

    /// 增加/减少用户的关注数
    private func incrementUserFollowingCount(userId: String, delta: Int) async throws {
        // 获取当前用户数据
        let user: User = try await client
            .from("users")
            .select("following_count")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        let newCount = max(0, (user.followingCount ?? 0) + delta)

        struct FollowingCountUpdate: Encodable, Sendable {
            let following_count: Int
            let updated_at: String
        }

        _ = try await client
            .from("users")
            .update(FollowingCountUpdate(
                following_count: newCount,
                updated_at: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: userId)
            .execute()
    }

    /// 增加/减少用户的粉丝数
    private func incrementUserFollowersCount(userId: String, delta: Int) async throws {
        // 获取当前用户数据
        let user: User = try await client
            .from("users")
            .select("followers_count")
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        let newCount = max(0, (user.followersCount ?? 0) + delta)

        struct FollowersCountUpdate: Encodable, Sendable {
            let followers_count: Int
            let updated_at: String
        }

        _ = try await client
            .from("users")
            .update(FollowersCountUpdate(
                followers_count: newCount,
                updated_at: ISO8601DateFormatter().string(from: Date())
            ))
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - MID RPC

    /// 调用后端 RPC，快速为指定用户生成/补发 MID，返回生成后的 mid 字符串
    func mintUserMID(userId: String) async throws -> String {
        // 优先用 select single 值（不同 Supabase SDK 版本返回结构可能不同）
        do {
            let response: PostgrestResponse<MintUserMIDRow> = try await client
                .rpc("mint_mid_for_user", params: MintUserMIDParams(uid: userId))
                .execute()
            if let value = response.value.mint_mid_for_user, !value.isEmpty {
                return value
            }
        } catch {
            // 某些版本 .value 直接是 String
            if let s = try? await client
                .rpc("mint_mid_for_user", params: MintUserMIDParams(uid: userId))
                .execute()
                .value as? String, !s.isEmpty {
                return s
            }
            throw error
        }

        // 再读一次用户，确保拿到 mid
        let user = try await fetchUser(id: userId)
        if let mid = user.mid, !mid.isEmpty {
            return mid
        }
        throw NSError(domain: "SupabaseService", code: -7, userInfo: [NSLocalizedDescriptionKey: "RPC 未返回 MID"])
    }

    // MARK: - Posts

    /// 批量加载帖子的作者信息
    private func populateAuthors(for posts: [Post]) async throws -> [Post] {
        guard !posts.isEmpty else { return posts }

        // 收集所有唯一的作者ID
        let authorIds = Array(Set(posts.map { $0.authorId }))

        // 批量获取作者信息
        let authors: [User] = try await client
            .from("users")
            .select()
            .in("id", values: authorIds)
            .execute()
            .value

        // 创建作者ID到作者对象的映射
        let authorMap = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })

        // 填充每个帖子的作者信息
        var updatedPosts = posts
        for i in 0..<updatedPosts.count {
            if let author = authorMap[updatedPosts[i].authorId] {
                updatedPosts[i].author = author
            }
        }

        return updatedPosts
    }

    /// 获取单个帖子
    func fetchPost(id: String) async throws -> Post {
        var post: Post = try await client
            .from("posts")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        // 加载作者信息
        let author = try await fetchUser(id: post.authorId)
        post.author = author

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
        return try await populateAuthors(for: posts)
    }

    /// 删除帖子（标记为 deleted 或直接删除）
    func deletePost(id: String) async throws {
        _ = try await client
            .from("posts")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// 隐藏帖子（此处用设置为 deleted 代替，因为模型没有 hidden）
    func hidePost(id: String) async throws {
        let payload = PostStatusPatch(status: PostStatus.deleted.rawValue, updated_at: ISO8601DateFormatter().string(from: Date()))
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
        return try await populateAuthors(for: posts)
    }

    /// 草稿发布（将 status 置为 published）
    func publishPost(id: String) async throws {
        let payload = PostStatusPatch(status: PostStatus.published.rawValue, updated_at: ISO8601DateFormatter().string(from: Date()))
        _ = try await client
            .from("posts")
            .update(payload)
            .eq("id", value: id)
            .execute()
    }

    /// 推荐流：展示所有已发布的内容（包含自己），按时间倒序
    func fetchRecommendedPosts(userId: String, limit: Int, offset: Int) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("status", value: PostStatus.published.rawValue)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return try await populateAuthors(for: posts)
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
        return try await populateAuthors(for: posts)
    }

    /// 关注流（取我关注的人发布的帖子）
    func fetchFollowingPosts(userId: String, limit: Int, offset: Int) async throws -> [Post] {
        let following: [FollowingRow] = try await client
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
        return try await populateAuthors(for: posts)
    }

    /// 搜索帖子（按文本、话题匹配；示例实现）
    func searchPosts(keyword: String, limit: Int, offset: Int) async throws -> [Post] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }

        let posts: [Post] = try await client
            .from("posts")
            .select()
            .eq("status", value: PostStatus.published.rawValue)
            .or("text.ilike.%\(kw)%,topics.ilike.%\(kw)%")
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
            .value
        return try await populateAuthors(for: posts)
    }

    // MARK: - Likes

    func hasLikedPost(userId: String, postId: String) async throws -> Bool {
        let rows: [LikesRowId] = try await client
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
        do {
            _ = try await client
                .from("likes")
                .insert(LikeInsert(user_id: userId, post_id: postId))
                .execute()
        } catch {
            let s = String(describing: error).lowercased()
            if s.contains("duplicate") || s.contains("unique") { return }
            throw error
        }
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
        _ = try? await client
            .rpc("decrement_post_collect_count", params: ["post_id": postId])
            .execute()
    }

    // MARK: - Collections

    func hasCollectedPost(userId: String, postId: String) async throws -> Bool {
        let rows: [GenericIdRow] = try await client
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
        do {
            _ = try await client
                .from("collections")
                .insert(CollectionInsert(user_id: userId, post_id: postId))
                .execute()
        } catch {
            let s = String(describing: error).lowercased()
            if s.contains("duplicate") || s.contains("unique") { return }
            throw error
        }
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
        _ = try? await client
            .rpc("decrement_post_collect_count", params: ["post_id": postId])
            .execute()
    }

    /// 获取用户收藏的帖子（简单做法：先查集合，再 in 取帖子）
    func fetchUserCollections(userId: String) async throws -> [Post] {
        let rows: [CollectionsRow] = try await client
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

    /// 批量加载评论的作者信息
    private func populateAuthorsForComments(for comments: [Comment]) async throws -> [Comment] {
        guard !comments.isEmpty else { return comments }

        // 收集所有唯一的作者ID
        let authorIds = Array(Set(comments.map { $0.authorId }))

        // 批量获取作者信息
        let authors: [User] = try await client
            .from("users")
            .select()
            .in("id", values: authorIds)
            .execute()
            .value

        // 创建作者ID到作者对象的映射
        let authorMap = Dictionary(uniqueKeysWithValues: authors.map { ($0.id, $0) })

        // 填充每个评论的作者信息
        var updatedComments = comments
        for i in 0..<updatedComments.count {
            if let author = authorMap[updatedComments[i].authorId] {
                updatedComments[i].author = author
            }
        }

        return updatedComments
    }

    func fetchComments(postId: String) async throws -> [Comment] {
        let comments: [Comment] = try await client
            .from("comments")
            .select()
            .eq("post_id", value: postId)
            .order("created_at", ascending: false)
            .execute()
            .value
        return try await populateAuthorsForComments(for: comments)
    }

    func createComment(postId: String, authorId: String, text: String, replyToId: String?) async throws -> Comment {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = CommentInsert(post_id: postId, author_id: authorId, text: text, reply_to_id: replyToId, created_at: now, updated_at: now)

        var inserted: Comment = try await client
            .from("comments")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        // 加载作者信息
        let author = try await fetchUser(id: authorId)
        inserted.author = author

        return inserted
    }
 
     /// 删除评论（仅作者可删），并减少帖子评论计数
     func deleteComment(id: String, postId: String) async throws {
         _ = try await client
             .from("comments")
             .delete()
             .eq("id", value: id)
             .execute()
         _ = try? await client
             .rpc("decrement_post_comment_count", params: ["post_id": postId])
             .execute()
     }
 
     /// 举报评论（写入 reports 表）
     func reportComment(reporterId: String, reportedUserId: String?, postId: String?, commentId: String?, reason: String?) async throws {
         let payload = ReportInsert(
             reporter_id: reporterId,
             reported_user_id: reportedUserId,
             post_id: postId,
             comment_id: commentId,
             reason: reason,
             created_at: ISO8601DateFormatter().string(from: Date())
         )
         _ = try await client
             .from("reports")
             .insert(payload)
             .execute()
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
        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        let payload = PostInsert(
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
        let payload = PostFullPatch(
            text: text,
            topics: topics,
            mood_tags: moodTags,
            city: city,
            is_anonymous: isAnonymous, // fixed key name
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
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("notifications")
            .update(NotificationReadUpdate(is_read: true, updated_at: now))
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

        let rows: [GenericIdRow] = try await client
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

        let rows: [GenericIdRow] = try await client
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
        let p1 = min(user1Id, user2Id)
        let p2 = max(user1Id, user2Id)

        let exist: [GenericIdRow] = try await client
            .from("conversations")
            .select("id")
            .eq("participant1_id", value: p1)
            .eq("participant2_id", value: p2)
            .limit(1)
            .execute()
            .value
        if let first = exist.first { return first.id }

        let now = ISO8601DateFormatter().string(from: Date())
        let id = UUID().uuidString
        let payload = ConversationInsert(
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
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = MessageInsert(
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

        _ = try? await client
            .from("conversations")
            .update(ConversationUpdate(last_message_at: now))
            .eq("id", value: conversationId)
            .execute()

        return inserted
    }

    func markMessageAsRead(messageId: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("messages")
            .update(MessageReadUpdate(is_read: true, updated_at: now))
            .eq("id", value: messageId)
            .execute()
    }

    // MARK: - Storage

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

    /// 直接使用 URLSession 上传以获取真实进度
    /// - Parameters:
    ///   - data: 媒体数据
    ///   - mime: MIME 类型，如 image/jpeg 或 video/mp4
    ///   - fileName: 文件名（可选，默认随机）
    ///   - folder: 目标文件夹，如 "posts/<uid>/images"
    ///   - bucket: 存储桶名，默认 "media"
    ///   - isPublic: 是否返回公开URL
    ///   - onProgress: 进度回调（0.0~1.0）
    /// - Returns: 上传后 URL 字符串
    func uploadPostMediaWithProgress(
        data: Data,
        mime: String,
        fileName: String? = nil,
        folder: String,
        bucket: String = "media",
        isPublic: Bool = true,
        onProgress: ((Double) -> Void)?
    ) async throws -> String {
        let name = fileName ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let sanitizedFolder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = "\(sanitizedFolder)/\(name)"

        // 构造上传 URL：/storage/v1/object/{bucket}/{path}
        let baseURL = URL(string: SupabaseConfig.url)!
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        // 认证：优先使用用户 token，回退到 anon key
        let accessToken = client.auth.session.accessToken
        let token = accessToken.isEmpty ? SupabaseConfig.anonKey : accessToken
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        // 自定义会话以监听上传进度
        final class UploadDelegate: NSObject, URLSessionTaskDelegate {
            let onProgress: ((Double) -> Void)?
            init(onProgress: ((Double) -> Void)?) { self.onProgress = onProgress }
            func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
                guard totalBytesExpectedToSend > 0 else { return }
                let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
                onProgress?(min(max(progress, 0.0), 1.0))
            }
        }

        let delegate = UploadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // 使用 continuation 包装异步上传
        let (responseData, response) = try await session.upload(for: request, from: data)

        // 关闭会话（避免持有 delegate）
        session.invalidateAndCancel()

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            // 显式抛出更友好的错误
            if http.statusCode == 413 || message.lowercased().contains("maximum allowed size") {
                throw NSError(domain: "Upload", code: 413, userInfo: [NSLocalizedDescriptionKey: "The object exceeded the maximum allowed size"])
            }
            throw NSError(domain: "Upload", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        // 上传完毕补齐 100%
        onProgress?(1.0)

        if isPublic {
            let url: URL = try client.storage.from(bucket).getPublicURL(path: path)
            return url.absoluteString
        } else {
            let signedURL: URL = try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 60 * 60 * 24)
            return signedURL.absoluteString
        }
    }

}

