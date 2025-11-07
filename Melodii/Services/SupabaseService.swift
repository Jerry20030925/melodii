//
//  SupabaseService.swift
//  Melodii
//
//  Core database service for Supabase operations
//

import Foundation
import Supabase
import Combine
import AVFoundation

@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    let client = SupabaseConfig.client
    
    // 网络重试配置
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    // 缓存配置
    private var userCache: [String: User] = [:]
    private var conversationCache: [String: Conversation] = [:]
    private let cacheExpiration: TimeInterval = 300 // 5分钟
    private var cacheTimestamps: [String: Date] = [:]
    
    // 批量操作队列
    private let batchQueue = DispatchQueue(label: "com.melodii.batch", qos: .utility)
    private var pendingOperations: [String: Any] = [:]
    
    private init() {
        setupCacheCleanup()
    }
    
    // MARK: - Cache Management
    
    /// 设置缓存清理定时器
    private func setupCacheCleanup() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredCache()
            }
        }
    }
    
    /// 清理过期缓存
    private func cleanupExpiredCache() {
        let now = Date()
        let expiredKeys = cacheTimestamps.compactMap { key, timestamp in
            now.timeIntervalSince(timestamp) > cacheExpiration ? key : nil
        }
        
        for key in expiredKeys {
            if key.hasPrefix("user_") {
                userCache.removeValue(forKey: String(key.dropFirst(5)))
            } else if key.hasPrefix("conversation_") {
                conversationCache.removeValue(forKey: String(key.dropFirst(13)))
            }
            cacheTimestamps.removeValue(forKey: key)
        }
        
        if !expiredKeys.isEmpty {
            print("🧹 清理了 \(expiredKeys.count) 个过期缓存项")
        }
    }
    
    /// 缓存用户数据
    private func cacheUser(_ user: User) {
        userCache[user.id] = user
        cacheTimestamps["user_\(user.id)"] = Date()
    }
    
    /// 从缓存获取用户
    private func getCachedUser(_ userId: String) -> User? {
        guard let timestamp = cacheTimestamps["user_\(userId)"],
              Date().timeIntervalSince(timestamp) < cacheExpiration else {
            return nil
        }
        return userCache[userId]
    }
    
    // MARK: - Network Helper Methods
    
    /// 执行带重试的网络请求
    private func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        operationName: String = "网络请求"
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxRetryAttempts {
            do {
                let result = try await operation()
                if attempt > 1 {
                    print("✅ \(operationName) 重试成功 (第 \(attempt) 次)")
                }
                return result
            } catch {
                lastError = error
                print("❌ \(operationName) 失败 (第 \(attempt) 次): \(error.localizedDescription)")
                
                // 如果不是最后一次尝试，等待后重试
                if attempt < maxRetryAttempts {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt - 1))
                    print("⏳ \(Int(delay))秒后重试...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(
            domain: "SupabaseService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "\(operationName)失败，已重试\(maxRetryAttempts)次"]
        )
    }
    
    // MARK: - User Operations

    func fetchUser(id: String) async throws -> User {
        // 先检查缓存
        if let cachedUser = getCachedUser(id) {
            return cachedUser
        }
        
        return try await executeWithRetry(operationName: "获取用户信息") {
            let user: User = try await self.client
                .from("users")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            
            // 缓存用户数据
            self.cacheUser(user)
            return user
        }
    }

    /// 更新用户基础信息（昵称、简介、头像、封面、兴趣）
    func updateUser(
        id: String,
        nickname: String? = nil,
        bio: String? = nil,
        avatarURL: String? = nil,
        coverURL: String? = nil,
        interests: [String]? = nil
    ) async throws {
        struct UserUpdate: Encodable {
            let nickname: String?
            let bio: String?
            let avatar_url: String?
            let cover_url: String?
            let interests: [String]?
            
            init(nickname: String? = nil, bio: String? = nil, avatarURL: String? = nil, coverURL: String? = nil, interests: [String]? = nil) {
                self.nickname = nickname
                self.bio = bio
                self.avatar_url = avatarURL
                self.cover_url = coverURL
                self.interests = interests
            }
        }
        
        let payload = UserUpdate(nickname: nickname, bio: bio, avatarURL: avatarURL, coverURL: coverURL, interests: interests)

        try await client
            .from("users")
            .update(payload)
            .eq("id", value: id)
            .execute()
        
        // 失效缓存，避免旧数据
        userCache.removeValue(forKey: id)
        cacheTimestamps.removeValue(forKey: "user_\(id)")
    }

    /// 完成用户的引导信息并写入（生日、兴趣、完成标记）
    func updateUserOnboardingInfo(userId: String, birthday: String?, interests: [String]?) async throws {
        struct OnboardingUpdate: Encodable {
            let is_onboarding_completed: Bool
            let birthday: String?
            let interests: [String]?
        }
        
        let payload = OnboardingUpdate(is_onboarding_completed: true, birthday: birthday, interests: interests)

        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()

        userCache.removeValue(forKey: userId)
        cacheTimestamps.removeValue(forKey: "user_\(userId)")
    }

    /// 更新用户的 MID 字段
    func updateUserMusicID(userId: String, newMID: String) async throws {
        try await client
            .from("users")
            .update(["mid": newMID])
            .eq("id", value: userId)
            .execute()

        userCache.removeValue(forKey: userId)
        cacheTimestamps.removeValue(forKey: "user_\(userId)")
    }
    
    // MARK: - Post Operations
    
    func createPost(authorId: String, text: String?, mediaURLs: [String], topics: [String], moodTags: [String], city: String?, isAnonymous: Bool) async throws -> Post {
        struct PostInsert: Encodable {
            let author_id: String
            let text: String?
            let media_urls: [String]
            let topics: [String]
            let mood_tags: [String]
            let city: String?
            let is_anonymous: Bool
            let status: String
        }
        
        let insertData = PostInsert(
            author_id: authorId,
            text: text,
            media_urls: mediaURLs,
            topics: topics,
            mood_tags: moodTags,
            city: city,
            is_anonymous: isAnonymous,
            status: "published"
        )
        
        let post: Post = try await client
            .from("posts")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
        
        return post
    }
    
    func updatePostFull(id: String, text: String?, topics: [String], moodTags: [String], city: String?, isAnonymous: Bool, mediaURLs: [String], status: PostStatus) async throws {
        struct PostUpdate: Encodable {
            let text: String?
            let topics: [String]
            let mood_tags: [String]
            let city: String?
            let is_anonymous: Bool
            let media_urls: [String]
            let status: String
            let updated_at: Date
        }
        
        let updateData = PostUpdate(
            text: text,
            topics: topics,
            mood_tags: moodTags,
            city: city,
            is_anonymous: isAnonymous,
            media_urls: mediaURLs,
            status: status.rawValue,
            updated_at: Date()
        )
        
        try await client
            .from("posts")
            .update(updateData)
            .eq("id", value: id)
            .execute()
    }
    
    func fetchPosts(limit: Int = 20, offset: Int = 0) async throws -> [Post] {
        let to = max(offset + limit - 1, offset)
        let posts: [Post] = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()
            .value
        
        return posts
    }

    /// 获取指定用户的发布内容
    func fetchUserPosts(userId: String, limit: Int = 20, offset: Int = 0) async throws -> [Post] {
        let to = max(offset + limit - 1, offset)
        let posts: [Post] = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("author_id", value: userId)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()
            .value
        return posts
    }

    /// 删除帖子
    func deletePost(id: String) async throws {
        try await client
            .from("posts")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// 隐藏帖子（软删除）
    func hidePost(id: String) async throws {
        try await client
            .from("posts")
            .update(["status": "hidden"]) 
            .eq("id", value: id)
            .execute()
    }
    
    // MARK: - Media Upload
    
    func uploadPostMediaWithProgress(data: Data, mime: String, fileName: String?, folder: String, bucket: String, isPublic: Bool, onProgress: @escaping (Double) -> Void) async throws -> String {
        let fileName = fileName ?? UUID().uuidString
        let path = "\(folder)/\(fileName)"
        
        // Simulate progress for now
        onProgress(0.5)
        
        let response = try await client.storage
            .from(bucket)
            .upload(path: path, file: data)
        
        onProgress(1.0)
        
        if isPublic {
            let publicURL = try client.storage
                .from(bucket)
                .getPublicURL(path: path)
            return publicURL.absoluteString
        } else {
            return path
        }
    }
    
    // MARK: - Interaction Operations
    
    func likePost(userId: String, postId: String) async throws {
        struct LikeInsert: Encodable {
            let user_id: String
            let post_id: String
        }
        
        let insertData = LikeInsert(user_id: userId, post_id: postId)
        
        try await client
            .from("post_likes")
            .insert(insertData)
            .execute()
    }
    
    func unlikePost(userId: String, postId: String) async throws {
        try await client
            .from("post_likes")
            .delete()
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .execute()
    }
    
    func hasLikedPost(userId: String, postId: String) async throws -> Bool {
        struct LikeRecord: Decodable {
            let id: String
        }
        
        let result: [LikeRecord] = try await client
            .from("post_likes")
            .select("id")
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .limit(1)
            .execute()
            .value
        
        return !result.isEmpty
    }

    /// 关注用户
    func followUser(followerId: String, followingId: String) async throws {
        struct Insert: Encodable { let follower_id: String; let following_id: String }
        let body = Insert(follower_id: followerId, following_id: followingId)
        try await client
            .from("follows")
            .insert(body)
            .execute()
    }

    /// 取消关注
    func unfollowUser(followerId: String, followingId: String) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: followerId)
            .eq("following_id", value: followingId)
            .execute()
    }

    /// 是否已关注
    func isFollowing(followerId: String, followingId: String) async throws -> Bool {
        struct C: Decodable { let count: Int }
        let res: [C] = try await client
            .from("follows")
            .select("count")
            .eq("follower_id", value: followerId)
            .eq("following_id", value: followingId)
            .execute()
            .value
        return res.first?.count ?? 0 > 0
    }

    /// 记录主页访问
    func recordUserProfileVisit(profileOwnerId: String, visitorId: String) async throws {
        struct Visit: Encodable { let profile_owner_id: String; let visitor_id: String }
        let payload = Visit(profile_owner_id: profileOwnerId, visitor_id: visitorId)
        try await client
            .from("profile_visits")
            .insert(payload)
            .execute()
    }
    
    func collectPost(userId: String, postId: String) async throws {
        struct CollectInsert: Encodable {
            let user_id: String
            let post_id: String
        }
        
        let insertData = CollectInsert(user_id: userId, post_id: postId)
        
        try await client
            .from("post_collections")
            .insert(insertData)
            .execute()
    }
    
    func uncollectPost(userId: String, postId: String) async throws {
        try await client
            .from("post_collections")
            .delete()
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .execute()
    }
    
    func hasCollectedPost(userId: String, postId: String) async throws -> Bool {
        struct CollectRecord: Decodable {
            let id: String
        }
        
        let result: [CollectRecord] = try await client
            .from("post_collections")
            .select("id")
            .eq("user_id", value: userId)
            .eq("post_id", value: postId)
            .limit(1)
            .execute()
            .value
        
        return !result.isEmpty
    }
    
    // MARK: - Messaging Operations
    
    func getOrCreateConversation(user1Id: String, user2Id: String) async throws -> String {
        // 1) 先查询是否已存在（两种顺序都查）
        do {
            struct Row: Decodable { let id: String }
            // or() 语法：participant1_id.eq.X,participant2_id.eq.Y OR participant1_id.eq.Y,participant2_id.eq.X
            let existing: [Row] = try await client
                .from("conversations")
                .select("id")
                .or("and(participant1_id.eq.\(user1Id),participant2_id.eq.\(user2Id)),and(participant1_id.eq.\(user2Id),participant2_id.eq.\(user1Id))")
                .limit(1)
                .execute()
                .value

            if let found = existing.first {
                return found.id
            }
        } catch {
            // 查询失败不应阻止后续插入，打印后继续
            print("⚠️ 查询会话失败（将尝试创建）: \(error)")
        }

        // 2) 不存在则创建（使用确定顺序，避免重复）
        struct InsertPayload: Encodable {
            let participant1_id: String
            let participant2_id: String
        }
        let payload = InsertPayload(participant1_id: min(user1Id, user2Id), participant2_id: max(user1Id, user2Id))

        struct Inserted: Decodable { let id: String }

        // 插入可能因并发而冲突（唯一索引建议加在数据库上：unique(participant1_id, participant2_id)）
        // 这里使用 upsert: false + 捕获冲突后再查一次，保证幂等。
        do {
            let inserted: Inserted = try await client
                .from("conversations")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        } catch {
            // 若冲突（已被并发创建），再查一次返回
            print("ℹ️ 插入会话可能冲突，回退到查询: \(error)")
            struct Row: Decodable { let id: String }
            let existing: [Row] = try await client
                .from("conversations")
                .select("id")
                .or("and(participant1_id.eq.\(user1Id),participant2_id.eq.\(user2Id)),and(participant1_id.eq.\(user2Id),participant2_id.eq.\(user1Id))")
                .limit(1)
                .execute()
                .value
            if let found = existing.first {
                return found.id
            }
            throw error
        }
    }

    // 按ID读取会话，并尽量补齐两侧用户（用于进入会话页）
    func fetchConversation(id: String, currentUserId: String) async throws -> Conversation {
        var conv: Conversation = try await client
            .from("conversations")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        // 尝试补齐 participant1/2（失败不阻塞）
        async let p1 = (try? fetchUser(id: conv.participant1Id))
        async let p2 = (try? fetchUser(id: conv.participant2Id))

        let (u1, u2) = await (p1, p2)
        conv.participant1 = u1
        conv.participant2 = u2

        // 可选：如果 lastMessage 需要填充，这里可以查询最近一条消息
        // 但你的模型 lastMessage 是可选，且列表页已有 lastMessageAt，所以可以跳过

        return conv
    }

    /// 获取用户的会话列表
    func fetchConversations(userId: String) async throws -> [Conversation] {
        var conversations: [Conversation] = try await client
            .from("conversations")
            .select()
            .or("participant1_id.eq.\(userId),participant2_id.eq.\(userId)")
            .order("last_message_at", ascending: false)
            .execute()
            .value

        // 并发补齐用户信息（失败不阻塞）
        try await withThrowingTaskGroup(of: (Int, User?, User?).self) { group in
            for (index, conv) in conversations.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, nil, nil) }
                    async let u1 = (try? self.fetchUser(id: conv.participant1Id))
                    async let u2 = (try? self.fetchUser(id: conv.participant2Id))
                    return (index, await u1, await u2)
                }
            }
            for try await (index, u1, u2) in group {
                conversations[index].participant1 = u1
                conversations[index].participant2 = u2
            }
        }
        return conversations
    }
    
    func sendMessage(conversationId: String, senderId: String, content: String, type: String = "text") async throws -> Message {
        print("🔍 [DEBUG] sendMessage called with:")
        print("  - conversationId: \(conversationId)")
        print("  - senderId: \(senderId)")
        print("  - content: \(content)")
        print("  - type: \(type)")
        
        struct MessageInsert: Encodable {
            let conversation_id: String
            let sender_id: String
            let receiver_id: String
            let content: String
            let message_type: String
        }
        
        do {
            // Get the other participant's ID from the conversation
            print("🔍 [DEBUG] Fetching conversation...")
            
            // Simple struct to match only what we need from database
            struct ConversationBasic: Decodable {
                let participant1_id: String
                let participant2_id: String
            }
            
            let conversationBasic: ConversationBasic = try await client
                .from("conversations")
                .select("participant1_id, participant2_id")
                .eq("id", value: conversationId)
                .single()
                .execute()
                .value
            print("🔍 [DEBUG] Conversation found: \(conversationBasic.participant1_id) <-> \(conversationBasic.participant2_id)")
                
            let receiverId = conversationBasic.participant1_id == senderId ? conversationBasic.participant2_id : conversationBasic.participant1_id
            print("🔍 [DEBUG] Receiver ID: \(receiverId)")
            
            let insertData = MessageInsert(
                conversation_id: conversationId,
                sender_id: senderId,
                receiver_id: receiverId,
                content: content,
                message_type: type
            )
            
            // Insert message without join first to avoid decoding issues
            struct SimpleMessage: Decodable {
                let id: String
                let conversation_id: String
                let sender_id: String
                let receiver_id: String
                let content: String
                let message_type: String
                let is_read: Bool
                let created_at: Date
                let updated_at: Date
            }
            
            print("🔍 [DEBUG] Inserting message to database...")
            let simpleMessage: SimpleMessage = try await client
                .from("messages")
                .insert(insertData)
                .select("*")
                .single()
                .execute()
                .value
            print("🔍 [DEBUG] Message inserted with ID: \(simpleMessage.id)")
                
            // Get sender info separately to avoid join issues
            print("🔍 [DEBUG] Fetching sender info...")
            let sender = try? await fetchUser(id: senderId)
            print("🔍 [DEBUG] Sender info: \(sender?.nickname ?? "nil")")
            
            // Create Message with manual init
            let message = Message(
                id: simpleMessage.id,
                conversationId: simpleMessage.conversation_id,
                senderId: simpleMessage.sender_id,
                receiverId: simpleMessage.receiver_id,
                sender: sender,
                content: simpleMessage.content,
                messageType: MessageType(rawValue: simpleMessage.message_type) ?? .text,
                isRead: simpleMessage.is_read,
                createdAt: simpleMessage.created_at,
                updatedAt: simpleMessage.updated_at
            )
            print("🔍 [DEBUG] Message object created successfully")
                
            // Update conversation's last message timestamp
            print("🔍 [DEBUG] Updating conversation timestamp...")
            try await client
                .from("conversations")
                .update(["last_message_at": Date().toISOString()])
                .eq("id", value: conversationId)
                .execute()
            print("🔍 [DEBUG] Conversation timestamp updated")
                
            print("✅ [DEBUG] sendMessage completed successfully")
            return message
        } catch {
            print("❌ [DEBUG] sendMessage failed: \(error)")
            print("❌ [DEBUG] Error details: \(error.localizedDescription)")
            throw error
        }
    }
    
    func markMessageAsRead(messageId: String) async throws {
        try await client
            .from("messages")
            .update(["is_read": true])
            .eq("id", value: messageId)
            .execute()
    }
    
    func getUnreadMessageCount(userId: String) async throws -> Int {
        do {
            struct MessageRecord: Decodable {
                let id: String
            }
            
            let result: [MessageRecord] = try await client
                .from("messages")
                .select("id")
                .eq("receiver_id", value: userId)
                .eq("is_read", value: false)
                .execute()
                .value
            
            return result.count
        } catch {
            print("❌ 获取未读消息数失败: \(error)")
            return 0
        }
    }
    
    // MARK: - Notification Operations
    
    func fetchUnreadNotificationCount(userId: String) async throws -> Int {
        struct CountResult: Decodable {
            let count: Int
        }
        
        let result: [CountResult] = try await client
            .from("notifications")
            .select("count")
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
            .value
        
        return result.first?.count ?? 0
    }
    
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
    
    func fetchPost(id: String) async throws -> Post {
        let post: Post = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("id", value: id)
            .single()
            .execute()
            .value
        
        return post
    }
    
    // MARK: - Custom Stickers
    
    func fetchCustomStickers(userId: String) async throws -> [CustomSticker] {
        let stickers: [CustomSticker] = try await client
            .from("custom_stickers")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return stickers
    }
    
    func createCustomSticker(userId: String, imageURL: String, name: String?) async throws -> CustomSticker {
        struct StickerInsert: Encodable {
            let user_id: String
            let image_url: String
            let name: String?
        }
        
        let insertData = StickerInsert(
            user_id: userId,
            image_url: imageURL,
            name: name
        )
        
        let sticker: CustomSticker = try await client
            .from("custom_stickers")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
        
        return sticker
    }
    
    func deleteCustomSticker(stickerId: String) async throws {
        try await client
            .from("custom_stickers")
            .delete()
            .eq("id", value: stickerId)
            .execute()
    }
    
    func uploadStickerImage(data: Data, userId: String, isPublic: Bool) async throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let folder = "stickers/\(userId)"
        
        return try await uploadPostMediaWithProgress(
            data: data,
            mime: "image/jpeg",
            fileName: fileName,
            folder: folder,
            bucket: "media",
            isPublic: isPublic
        ) { _ in }
    }

    // MARK: - Compatibility Wrappers (matching existing view call sites)

    /// 兼容旧调用：上传用户媒体（使用默认 bucket: media, public: true）
    func uploadUserMedia(data: Data, mime: String, fileName: String?, folder: String) async throws -> String {
        return try await uploadPostMediaWithProgress(
            data: data,
            mime: mime,
            fileName: fileName,
            folder: folder,
            bucket: "media",
            isPublic: true
        ) { _ in }
    }


    // MARK: - User Media Upload
    /// 上传用户头像或封面等媒体，返回可用 URL
    func uploadUserMedia(data: Data, userId: String, fileName: String? = nil, isPublic: Bool = true) async throws -> String {
        let name = fileName ?? "\(UUID().uuidString).jpg"
        let folder = "users/\(userId)"
        return try await uploadPostMediaWithProgress(
            data: data,
            mime: "image/jpeg",
            fileName: name,
            folder: folder,
            bucket: "media",
            isPublic: isPublic,
            onProgress: { _ in }
        )
    }

    
    // MARK: - Presence Operations
    
    func setOnline(userId: String, online: Bool) async throws {
        struct PresenceUpdate: Encodable {
            let is_online: Bool
            let last_seen: String
        }
        
        let payload = PresenceUpdate(is_online: online, last_seen: Date().toISOString())
        
        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }
    
    func touchLastSeen(userId: String) async throws {
        try await client
            .from("users")
            .update(["last_seen": Date().toISOString()])
            .eq("id", value: userId)
            .execute()
    }
    
    // MARK: - Voice Message Operations
    
    func uploadVoiceMessage(data: Data, userId: String) async throws -> String {
        let fileName = "\(UUID().uuidString).m4a"
        let folder = "voices/\(userId)"
        
        // 优先上传到 audio 存储桶；若失败则回退到 media 存储桶
        do {
            return try await uploadPostMediaWithProgress(
                data: data,
                mime: "audio/m4a",
                fileName: fileName,
                folder: folder,
                bucket: "audio",
                isPublic: true
            ) { _ in }
        } catch {
            print("⚠️ 上传到 'audio' 存储桶失败，回退到 'media'：\(error)")
            return try await uploadPostMediaWithProgress(
                data: data,
                mime: "audio/m4a",
                fileName: fileName,
                folder: folder,
                bucket: "media",
                isPublic: true
            ) { _ in }
        }
    }
    
    func getAudioDuration(from url: URL) async -> TimeInterval {
        do {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            print("❌ 获取音频时长失败: \(error)")
            return 0
        }
    }

    // MARK: - Comment Operations
    func fetchComments(postId: String, limit: Int = 50, offset: Int = 0) async throws -> [Comment] {
        let to = max(offset + limit - 1, offset)
        let comments: [Comment] = try await client
            .from("comments")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("post_id", value: postId)
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()
            .value
        return comments
    }
    
    func createComment(postId: String, authorId: String, text: String, replyToId: String? = nil) async throws -> Comment {
        struct CommentInsert: Encodable {
            let post_id: String
            let author_id: String
            let text: String
            let reply_to_id: String?
        }
        
        let insertData = CommentInsert(
            post_id: postId,
            author_id: authorId,
            text: text,
            reply_to_id: replyToId
        )
        
        let comment: Comment = try await client
            .from("comments")
            .insert(insertData)
            .select("""
                *,
                author:users!author_id(*),
                post:posts!post_id(*)
            """)
            .single()
            .execute()
            .value
            
        return comment
    }
    
    func deleteComment(id: String, postId: String) async throws {
        try await client
            .from("comments")
            .delete()
            .eq("id", value: id)
            .eq("post_id", value: postId)
            .execute()
    }
    
    func reportComment(reporterId: String, reportedUserId: String, postId: String, commentId: String, reason: String?) async throws {
        struct ReportInsert: Encodable {
            let reporter_id: String
            let reported_user_id: String
            let post_id: String
            let comment_id: String
            let reason: String?
            let report_type: String
        }
        
        let insertData = ReportInsert(
            reporter_id: reporterId,
            reported_user_id: reportedUserId,
            post_id: postId,
            comment_id: commentId,
            reason: reason,
            report_type: "comment"
        )
        
        try await client
            .from("reports")
            .insert(insertData)
            .execute()
    }
    
    
    // MARK: - Additional Methods
    
    func fetchUserCollections(userId: String) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("post_collections")
            .select("""
                post:posts!post_id(
                    *,
                    author:users!author_id(*)
                )
            """)
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return posts
    }
    
    func fetchDraftPosts(userId: String) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("author_id", value: userId)
            .eq("status", value: "draft")
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return posts
    }
    
    func publishPost(id: String) async throws {
        try await client
            .from("posts")
            .update(["status": "published"])
            .eq("id", value: id)
            .execute()
    }
    
    
    func fetchUserProfile(id: String) async throws -> User {
        return try await fetchUser(id: id)
    }
    
    func markNotificationAsRead(id: String) async throws {
        try await client
            .from("notifications")
            .update(["is_read": true])
            .eq("id", value: id)
            .execute()
    }
    
    func fetchTrendingPosts(limit: Int = 20) async throws -> [Post] {
        return try await fetchPosts(limit: limit, offset: 0)
    }
    
    func fetchProfileVisits(userId: String) async throws -> [ProfileVisit] {
        let visits: [ProfileVisit] = try await client
            .from("profile_visits")
            .select("""
                *,
                visitor:users!visitor_id(*)
            """)
            .eq("profile_owner_id", value: userId)
            .order("visited_at", ascending: false)
            .execute()
            .value
        
        return visits
    }
    
    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        let users: [User] = try await client
            .from("users")
            .select()
            .or("nickname.ilike.%\(query)%,mid.ilike.%\(query)%")
            .limit(limit)
            .execute()
            .value
        
        return users
    }
    
    func fetchMessages(conversationId: String, limit: Int = 50, offset: Int = 0) async throws -> [Message] {
        let to = max(offset + limit - 1, offset)
        
        // Fetch messages without joins first
        struct SimpleMessage: Decodable {
            let id: String
            let conversation_id: String
            let sender_id: String
            let receiver_id: String
            let content: String
            let message_type: String
            let is_read: Bool
            let created_at: Date
            let updated_at: Date
        }
        
        let simpleMessages: [SimpleMessage] = try await client
            .from("messages")
            .select("*")
            .eq("conversation_id", value: conversationId)
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()
            .value
        
        // Convert to Message objects with sender info
        var messages: [Message] = []
        for simple in simpleMessages {
            let sender = try? await fetchUser(id: simple.sender_id)
            let message = Message(
                id: simple.id,
                conversationId: simple.conversation_id,
                senderId: simple.sender_id,
                receiverId: simple.receiver_id,
                sender: sender,
                content: simple.content,
                messageType: MessageType(rawValue: simple.message_type) ?? .text,
                isRead: simple.is_read,
                createdAt: simple.created_at,
                updatedAt: simple.updated_at
            )
            messages.append(message)
        }
        
        return messages
    }
    
    func fetchRecommendedPosts(userId: String? = nil, limit: Int = 20, offset: Int = 0) async throws -> [Post] {
        // For now, return trending posts as recommendations
        return try await fetchPosts(limit: limit, offset: offset)
    }
    
    func fetchFollowingPosts(userId: String, limit: Int = 20, offset: Int = 0) async throws -> [Post] {
        // First get the user's following list
        struct FollowRow: Codable {
            let following_id: String
        }
        
        let following: [FollowRow] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userId)
            .execute()
            .value
        
        guard !following.isEmpty else {
            return [] // User is not following anyone
        }
        
        let followingIds = following.map { $0.following_id }
        let to = max(offset + limit - 1, offset)
        
        let posts: [Post] = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .in("author_id", values: followingIds)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .range(from: offset, to: to)
            .execute()
            .value
        
        return posts
    }

    // MARK: - Melomoment & Mutual Following

    /// 获取与我互相关注的用户ID列表
    func fetchMutualFollowingIds(userId: String) async throws -> [String] {
        struct FRow: Codable { let following_id: String }
        struct RRow: Codable { let follower_id: String }

        // 我关注了谁
        let following: [FRow] = try await client
            .from("follows")
            .select("following_id")
            .eq("follower_id", value: userId)
            .execute()
            .value

        // 谁关注了我
        let followers: [RRow] = try await client
            .from("follows")
            .select("follower_id")
            .eq("following_id", value: userId)
            .execute()
            .value

        let followingIds = Set(following.map { $0.following_id })
        let followerIds = Set(followers.map { $0.follower_id })
        let mutual = followingIds.intersection(followerIds)
        return Array(mutual)
    }

    /// 拉取互关用户的 Melomoment（使用 posts 表，topics 包含 "melomoment"）
    func fetchMelomoments(userId: String, limit: Int = 30) async throws -> [Post] {
        let mutualIds = try await fetchMutualFollowingIds(userId: userId)
        guard !mutualIds.isEmpty else { return [] }

        // 拉取互关作者的已发布帖子
        let posts: [Post] = try await client
            .from("posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .in("author_id", values: mutualIds)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        // 客户端过滤 topics 包含 "melomoment"
        let filtered = posts.filter { $0.topics.contains("melomoment") }
        return filtered
    }

    // MARK: - Moments (独立数据表)

    /// 拉取互关好友的 Moments（使用 moments 表）
    func fetchMoments(userId: String, limit: Int = 30) async throws -> [Moment] {
        let mutualIds = try await fetchMutualFollowingIds(userId: userId)
        guard !mutualIds.isEmpty else { return [] }

        let moments: [Moment] = try await client
            .from("moments")
            .select(
                """
                *,
                author:users!author_id(*)
                """
            )
            .in("author_id", values: mutualIds)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return moments
    }

    /// 创建一个新的 Moment（插入 moments 表）
    func createMoment(authorId: String, mediaURL: String, caption: String? = nil) async throws -> Moment {
        struct MomentInsert: Encodable {
            let author_id: String
            let media_url: String
            let caption: String?
        }

        let insertData = MomentInsert(author_id: authorId, media_url: mediaURL, caption: caption)

        let moment: Moment = try await client
            .from("moments")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
        return moment
    }
}

// MARK: - Helper Extensions

extension Date {
    func toISOString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

