//
//  Models.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import SwiftData

// MARK: - User Model
@Model
final class User: Codable, Hashable {
    @Attribute(.unique) var id: String
    // 唯一对外展示的用户编号（MID），用于搜索
    var mid: String?
    var appleUserId: String?
    var nickname: String
    var avatarURL: String?
    var coverImageURL: String?  // 封面图
    var bio: String?
    var birthday: Date?
    var interests: [String]
    var isOnboardingCompleted: Bool
    var followingCount: Int?
    var followersCount: Int?
    var likesCount: Int?
    var createdAt: Date
    var updatedAt: Date

    // 关系
    @Relationship(deleteRule: .cascade) var posts: [Post]?
    @Relationship(deleteRule: .cascade) var comments: [Comment]?

    init(id: String = UUID().uuidString,
         appleUserId: String? = nil,
         mid: String? = nil,
         nickname: String,
         avatarURL: String? = nil,
         coverImageURL: String? = nil,
         bio: String? = nil,
         birthday: Date? = nil,
         interests: [String] = [],
         isOnboardingCompleted: Bool = false,
         followingCount: Int? = nil,
         followersCount: Int? = nil,
         likesCount: Int? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.appleUserId = appleUserId
        self.mid = mid
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.coverImageURL = coverImageURL
        self.bio = bio
        self.birthday = birthday
        self.interests = interests
        self.isOnboardingCompleted = isOnboardingCompleted
        self.followingCount = followingCount
        self.followersCount = followersCount
        self.likesCount = likesCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var initials: String {
        String(nickname.prefix(1))
    }

    // Codable支持（用于Supabase）
    enum CodingKeys: String, CodingKey {
        case id, appleUserId = "apple_user_id", mid, nickname, avatarURL = "avatar_url"
        case coverImageURL = "cover_image_url", bio, birthday, interests
        case isOnboardingCompleted = "is_onboarding_completed"
        case followingCount = "following_count"
        case followersCount = "followers_count"
        case likesCount = "likes_count"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        appleUserId = try container.decodeIfPresent(String.self, forKey: .appleUserId)
        mid = try container.decodeIfPresent(String.self, forKey: .mid)
        nickname = try container.decode(String.self, forKey: .nickname)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        coverImageURL = try container.decodeIfPresent(String.self, forKey: .coverImageURL)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        birthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        isOnboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .isOnboardingCompleted) ?? false
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(appleUserId, forKey: .appleUserId)
        try container.encodeIfPresent(mid, forKey: .mid)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(coverImageURL, forKey: .coverImageURL)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(birthday, forKey: .birthday)
        try container.encode(interests, forKey: .interests)
        try container.encode(isOnboardingCompleted, forKey: .isOnboardingCompleted)
        try container.encodeIfPresent(followingCount, forKey: .followingCount)
        try container.encodeIfPresent(followersCount, forKey: .followersCount)
        try container.encodeIfPresent(likesCount, forKey: .likesCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Post Model
@Model
final class Post: Codable {
    @Attribute(.unique) var id: String
    var authorId: String
    @Relationship var author: User
    var text: String?
    var mediaURLs: [String]
    var topics: [String]
    var moodTags: [String]  // 情绪标签（#开心 #孤独等）
    var city: String?  // 城市信息
    var isAnonymous: Bool  // 是否匿名发布
    var likeCount: Int
    var commentCount: Int
    var collectCount: Int
    var status: PostStatus
    var createdAt: Date
    var updatedAt: Date

    // 关系
    @Relationship(deleteRule: .cascade) var comments: [Comment]?

    init(id: String = UUID().uuidString,
         author: User,
         text: String? = nil,
         mediaURLs: [String] = [],
         topics: [String] = [],
         moodTags: [String] = [],
         city: String? = nil,
         isAnonymous: Bool = false,
         likeCount: Int = 0,
         commentCount: Int = 0,
         collectCount: Int = 0,
         status: PostStatus = .published,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.authorId = author.id
        self.author = author
        self.text = text
        self.mediaURLs = mediaURLs
        self.topics = topics
        self.moodTags = moodTags
        self.city = city
        self.isAnonymous = isAnonymous
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.collectCount = collectCount
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, authorId = "author_id", text, mediaURLs = "media_urls", topics
        case moodTags = "mood_tags", city, isAnonymous = "is_anonymous"
        case likeCount = "like_count", commentCount = "comment_count"
        case collectCount = "collect_count", status
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAuthorId = try container.decode(String.self, forKey: .authorId)

        id = try container.decode(String.self, forKey: .id)
        authorId = decodedAuthorId
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mediaURLs = try container.decode([String].self, forKey: .mediaURLs)
        topics = try container.decode([String].self, forKey: .topics)
        moodTags = try container.decodeIfPresent([String].self, forKey: .moodTags) ?? []
        city = try container.decodeIfPresent(String.self, forKey: .city)
        isAnonymous = try container.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        collectCount = try container.decode(Int.self, forKey: .collectCount)
        status = try container.decode(PostStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // author需要单独加载
        author = User(id: decodedAuthorId, nickname: "Loading...")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(authorId, forKey: .authorId)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(mediaURLs, forKey: .mediaURLs)
        try container.encode(topics, forKey: .topics)
        try container.encode(moodTags, forKey: .moodTags)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encode(isAnonymous, forKey: .isAnonymous)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encode(collectCount, forKey: .collectCount)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum PostStatus: String, Codable {
    case draft = "draft"           // 草稿
    case published = "published"   // 已发布
    case reviewing = "reviewing"   // 审核中
    case rejected = "rejected"     // 审核未通过
    case deleted = "deleted"       // 已删除
}

// MARK: - Comment Model
@Model
final class Comment: Codable {
    @Attribute(.unique) var id: String
    var postId: String
    @Relationship var post: Post
    var authorId: String
    @Relationship var author: User
    var text: String
    var likeCount: Int
    var replyToId: String? // 回复的评论ID
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         post: Post,
         author: User,
         text: String,
         likeCount: Int = 0,
         replyToId: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.postId = post.id
        self.post = post
        self.authorId = author.id
        self.author = author
        self.text = text
        self.likeCount = likeCount
        self.replyToId = replyToId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, postId = "post_id", authorId = "author_id", text
        case likeCount = "like_count", replyToId = "reply_to_id"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPostId = try container.decode(String.self, forKey: .postId)
        let decodedAuthorId = try container.decode(String.self, forKey: .authorId)

        id = try container.decode(String.self, forKey: .id)
        postId = decodedPostId
        authorId = decodedAuthorId
        text = try container.decode(String.self, forKey: .text)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        replyToId = try container.decodeIfPresent(String.self, forKey: .replyToId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // post 和 author 需要单独加载
        post = Post(author: User(nickname: "Loading..."))
        author = User(id: decodedAuthorId, nickname: "Loading...")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(postId, forKey: .postId)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(text, forKey: .text)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encodeIfPresent(replyToId, forKey: .replyToId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Like Model (点赞)
struct Like: Codable, Identifiable {
    let id: String
    let userId: String
    let postId: String?
    let commentId: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", postId = "post_id"
        case commentId = "comment_id", createdAt = "created_at"
    }
}

// MARK: - Collection Model (收藏)
struct Collection: Codable, Identifiable {
    let id: String
    let userId: String
    let postId: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", postId = "post_id", createdAt = "created_at"
    }
}

// MARK: - Notification Model (通知)
struct Notification: Codable, Identifiable {
    let id: String
    let userId: String // 接收通知的用户
    let actorId: String // 触发通知的用户
    let type: NotificationType
    let postId: String?
    let commentId: String?
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", actorId = "actor_id", type
        case postId = "post_id", commentId = "comment_id"
        case isRead = "is_read", createdAt = "created_at"
    }
}

enum NotificationType: String, Codable {
    case like = "like"           // 点赞
    case comment = "comment"     // 评论
    case reply = "reply"         // 回复
    case follow = "follow"       // 关注
}

// MARK: - Follow Model (关注)
struct Follow: Codable, Identifiable {
    let id: String
    let followerId: String  // 关注者（粉丝）
    let followingId: String // 被关注者
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case followerId = "follower_id"
        case followingId = "following_id"
        case createdAt = "created_at"
    }
}

// MARK: - Topic Model (话题)
struct Topic: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let postCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case postCount = "post_count", createdAt = "created_at"
    }
}

// MARK: - Conversation Model (会话)
struct Conversation: Codable, Identifiable {
    let id: String
    let participant1Id: String
    let participant2Id: String
    var participant1: User?
    var participant2: User?
    var lastMessage: Message?
    let lastMessageAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case participant1Id = "participant1_id"
        case participant2Id = "participant2_id"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 获取对方用户（相对于当前用户）
    func getOtherUser(currentUserId: String) -> User? {
        if participant1Id == currentUserId {
            return participant2
        } else {
            return participant1
        }
    }
}

// MARK: - Message Model (私信)
struct Message: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let receiverId: String
    var sender: User?
    let content: String
    let messageType: MessageType
    let isRead: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case content
        case messageType = "message_type"
        case isRead = "is_read"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum MessageType: String, Codable {
    case text = "text"           // 文字消息
    case image = "image"         // 图片消息
    case voice = "voice"         // 语音消息
    case system = "system"       // 系统消息
}
