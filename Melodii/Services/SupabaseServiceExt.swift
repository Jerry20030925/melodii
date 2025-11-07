//
//  SupabaseServiceExt.swift
//  Melodii
//
//  SupabaseService 扩展：增强帖子功能
//

import SwiftUI
import Foundation
import Supabase

// MARK: - 音乐推荐数据模型

struct MusicRecommendation: Identifiable, Codable {
    let id = UUID()
    let title: String
    let artist: String
    let coverURL: String
    let audioURL: String
    let category: MusicCategory
    let usageCount: Int
    let isPopular: Bool
    
    static let trending: [MusicRecommendation] = [
        MusicRecommendation(
            title: "夏日微风",
            artist: "轻松音乐团队",
            coverURL: "https://example.com/cover1.jpg",
            audioURL: "https://example.com/audio1.mp3",
            category: .chill,
            usageCount: 1520,
            isPopular: true
        ),
        MusicRecommendation(
            title: "城市夜光",
            artist: "都市节拍",
            coverURL: "https://example.com/cover2.jpg",
            audioURL: "https://example.com/audio2.mp3",
            category: .trending,
            usageCount: 2100,
            isPopular: true
        ),
        MusicRecommendation(
            title: "森林清晨",
            artist: "自然之声",
            coverURL: "https://example.com/cover3.jpg",
            audioURL: "https://example.com/audio3.mp3",
            category: .nature,
            usageCount: 890,
            isPopular: false
        ),
        MusicRecommendation(
            title: "专注时光",
            artist: "学习音乐",
            coverURL: "https://example.com/cover4.jpg",
            audioURL: "https://example.com/audio4.mp3",
            category: .study,
            usageCount: 1340,
            isPopular: true
        ),
        MusicRecommendation(
            title: "活力四射",
            artist: "动感音乐",
            coverURL: "https://example.com/cover6.jpg",
            audioURL: "https://example.com/audio6.mp3",
            category: .energetic,
            usageCount: 1120,
            isPopular: true
        )
    ]
}

enum MusicCategory: String, CaseIterable, Codable {
    case trending = "流行趋势"
    case chill = "轻松氛围"
    case energetic = "活力四射"
    case nature = "自然音效"
    case study = "专注学习"
    case romantic = "浪漫情怀"
    
    var emoji: String {
        switch self {
        case .trending: return "🔥"
        case .chill: return "😌"
        case .energetic: return "⚡"
        case .nature: return "🌲"
        case .study: return "📚"
        case .romantic: return "💕"
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .trending: return [.red, .orange]
        case .chill: return [.blue, .cyan]
        case .energetic: return [.yellow, .orange]
        case .nature: return [.green, .mint]
        case .study: return [.purple, .indigo]
        case .romantic: return [.pink, .red]
        }
    }
}

// MARK: - 增强帖子视图模型

struct PostPreviewCard: View {
    let text: String
    let mediaURLs: [String]
    let selectedMusic: MusicRecommendation?
    let selectedTemplate: CreativeTemplate?
    let appliedFilters: [ImageFilter]
    let mood: CreativeMood
    let author: User
    let isAnonymous: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("预览帖子")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 使用增强的帖子卡片进行预览
            EnhancedPostCardView(
                post: Post(
                    id: "preview",
                    author: author,
                    text: text.isEmpty ? "这是您的创作预览..." : text,
                    mediaURLs: mediaURLs,
                    topics: [],
                    moodTags: [],
                    city: nil,
                    isAnonymous: isAnonymous,
                    likeCount: 0,
                    commentCount: 0,
                    collectCount: 0,
                    status: .published,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                enableImageViewer: false
            )
            .overlay(
                // 预览覆盖层
                Color.black.opacity(0.1)
                    .overlay(
                        VStack {
                            Text("预览模式")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                            
                            Spacer()
                        }
                        .padding()
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .allowsHitTesting(false)
        }
    }
}

struct MediaFullscreenView: View {
    let url: String
    let filters: [ImageFilter]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .applyFilters(filters)
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        // 保存图片逻辑
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

struct EnhancedMediaViewer: View {
    let urls: [String]
    let initialIndex: Int
    let post: Post
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    
    init(urls: [String], initialIndex: Int, post: Post) {
        self.urls = urls
        self.initialIndex = initialIndex
        self.post = post
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        AsyncImage(url: URL(string: url)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ProgressView()
                                .tint(.white)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("\(currentIndex + 1) / \(urls.count)")
                        .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        // 保存图片逻辑
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - SupabaseService 增强功能扩展

extension SupabaseService {
    /// 创建增强帖子（支持音乐、模板、滤镜等）
    func createEnhancedPost(authorId: String, data: EnhancedPostData) async throws -> Post {
        // 构建增强帖子数据
        struct EnhancedPostInsert: Encodable {
            let author_id: String
            let text: String?
            let media_urls: [String]
            let music_url: String?
            let template_id: String?
            let applied_filters: [String]
            let creative_mood: String
            let topics: [String]
            let mood_tags: [String]
            let city: String?
            let is_anonymous: Bool
            let status: String
        }
        
        let insertData = EnhancedPostInsert(
            author_id: authorId,
            text: data.text.isEmpty ? nil : data.text,
            media_urls: data.mediaURLs,
            music_url: data.musicURL,
            template_id: data.templateId,
            applied_filters: data.filters,
            creative_mood: data.mood,
            topics: data.topics,
            mood_tags: data.moodTags,
            city: data.city,
            is_anonymous: data.isAnonymous,
            status: "published"
        )
        
        // 插入到数据库
        let insertedPost: Post = try await client
            .from("enhanced_posts")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
        
        print("✅ 增强帖子创建成功: \(insertedPost.id)")
        return insertedPost
    }
    
    /// 获取增强帖子列表（包含音乐信息）
    func fetchEnhancedPosts(limit: Int = 20, offset: Int = 0) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("enhanced_posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        
        return posts
    }
    
    /// 获取带音乐的帖子
    func fetchPostsWithMusic(limit: Int = 20) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("enhanced_posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .not("music_url", operator: .is, value: "null")
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return posts
    }
    
    /// 根据心情筛选帖子
    func fetchPostsByMood(_ mood: CreativeMood, limit: Int = 20) async throws -> [Post] {
        let posts: [Post] = try await client
            .from("enhanced_posts")
            .select("""
                *,
                author:users!author_id(*)
            """)
            .eq("creative_mood", value: mood.rawValue)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return posts
    }
    
    /// 获取音乐推荐
    func fetchMusicRecommendations(category: MusicCategory? = nil) async throws -> [MusicRecommendation] {
        // 实际应用中应该从数据库获取
        // 这里返回模拟数据
        var recommendations = MusicRecommendation.trending
        
        if let category = category {
            recommendations = recommendations.filter { $0.category == category }
        }
        
        return recommendations.sorted { $0.usageCount > $1.usageCount }
    }
    
    /// 更新帖子音乐使用次数
    func incrementMusicUsage(musicId: String) async throws {
        // 实际应用中应该更新音乐使用统计
        print("📊 更新音乐使用统计: \(musicId)")
    }
}
