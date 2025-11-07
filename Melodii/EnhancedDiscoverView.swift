//
//  EnhancedDiscoverView.swift
//  Melodii
//
//  全新首页体验：动态故事模式、音乐发现、3D效果
//

import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import Combine

// MARK: - 首页模式枚举

enum DiscoverMode: String, CaseIterable {
    case stories = "故事"
    case music = "音乐"
    case trending = "热门"
    case following = "关注"
    
    var icon: String {
        switch self {
        case .stories: return "book.fill"
        case .music: return "music.note"
        case .trending: return "flame.fill"
        case .following: return "person.2.fill"
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .stories: return [.purple, .pink]
        case .music: return [.blue, .cyan]
        case .trending: return [.orange, .red]
        case .following: return [.green, .mint]
        }
    }
}

// MARK: - 故事卡片数据

struct StoryCard: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let preview: String
    let coverURL: String?
    let musicURL: String?
    let posts: [Post]
    let createdAt: Date
}

// MARK: - 主视图

struct EnhancedDiscoverView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    
    @State private var selectedMode: DiscoverMode = .stories
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var headerOffset: CGFloat = 0
    
    // 数据状态
    @State private var storyCards: [StoryCard] = []
    @State private var musicRecommendations: [MusicRecommendation] = []
    @State private var trendingPosts: [Post] = []
    @State private var followingPosts: [Post] = []
    
    // 交互状态
    @State private var selectedStoryIndex: Int?
    @State private var currentMusicIndex = 0
    @State private var isPlayingMusic = false
    @State private var showMusicPlayer = false
    
    // 3D效果状态
    @State private var rotationAngle: Double = 0
    @State private var parallaxOffset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            headerSection
                            
                            modeTabBar
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            
                            contentView
                        }
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(key: ScrollOffsetPreferenceKey.self, 
                                             value: geometry.frame(in: .named("scroll")).minY)
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                        headerOffset = min(0, value + 100)
                        parallaxOffset = value * 0.3
                    }
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadData()
            }
            .sheet(isPresented: $showMusicPlayer) {
                Text("Music Player Coming Soon")
                    .padding()
                    .navigationTitle("Music Player")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    // MARK: - 背景视图
    
    private var backgroundView: some View {
        ZStack {
            // 动态渐变背景
            LinearGradient(
                colors: [
                    selectedMode.gradient[0].opacity(0.15),
                    selectedMode.gradient[1].opacity(0.1),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: selectedMode)
            
            // 浮动几何图形
            GeometryReader { geometry in
                ForEach(0..<8, id: \.self) { index in
                    FloatingShape(
                        size: CGFloat.random(in: 20...80),
                        color: selectedMode.gradient[index % 2].opacity(0.1),
                        offset: CGPoint(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        ),
                        rotationSpeed: Double.random(in: 10...30),
                        scrollOffset: scrollOffset
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - 头部区域
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // 状态栏占位
            Color.clear.frame(height: 44)
            
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        // 动态问候
                        Text(getGreeting())
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        
                        // 时间指示器
                        TimeIndicatorView()
                    }
                    
                    Text("发现你感兴趣的内容")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    // 搜索按钮
                    Button {
                        showSearch = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                            
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // 用户头像
                    if let user = authService.currentUser {
                        NavigationLink(destination: UserProfileView(user: user)) {
                            UserAvatarView(user: user, size: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .offset(y: headerOffset)
        .animation(.easeOut(duration: 0.3), value: headerOffset)
    }
    
    // MARK: - 模式选择栏
    
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DiscoverMode.allCases, id: \.self) { mode in
                    ModeTabButton(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                selectedMode = mode
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    // MARK: - 内容视图
    
    private var contentView: some View {
        Group {
            switch selectedMode {
            case .stories:
                StoriesView(
                    stories: storyCards,
                    selectedIndex: $selectedStoryIndex
                )
            case .music:
                MusicDiscoveryView(
                    recommendations: musicRecommendations,
                    currentIndex: $currentMusicIndex,
                    isPlaying: $isPlayingMusic,
                    showPlayer: $showMusicPlayer
                )
            case .trending:
                TrendingView(posts: trendingPosts)
            case .following:
                FollowingView(posts: followingPosts)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }
    
    // MARK: - 数据加载
    
    private func loadData() async {
        // 加载故事数据
        storyCards = generateMockStories()
        
        // 加载音乐推荐
        musicRecommendations = generateMockMusic()
        
        // 加载真实数据
        await loadTrendingPosts()
        await loadFollowingPosts()
    }
    
    private func loadTrendingPosts() async {
        do {
            trendingPosts = try await supabaseService.fetchTrendingPosts(limit: 20)
        } catch {
            print("加载热门内容失败: \(error)")
        }
    }
    
    private func loadFollowingPosts() async {
        guard let userId = authService.currentUser?.id else { return }
        do {
            followingPosts = try await supabaseService.fetchFollowingPosts(userId: userId, limit: 20, offset: 0)
        } catch {
            print("加载关注内容失败: \(error)")
        }
    }
    
    // MARK: - 辅助方法
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "早安 ☀️"
        case 12..<18: return "午好 🌤️"
        case 18..<22: return "晚好 🌅"
        default: return "夜深了 🌙"
        }
    }
    
    private func generateMockStories() -> [StoryCard] {
        // 这里应该从服务器获取，暂时使用模拟数据
        return [
            StoryCard(
                title: "城市夜色",
                author: "摄影师小李",
                preview: "记录都市夜晚的霓虹与静谧...",
                coverURL: nil,
                musicURL: nil,
                posts: [],
                createdAt: Date()
            ),
            StoryCard(
                title: "咖啡时光",
                author: "文艺青年",
                preview: "在咖啡香中品味生活的美好...",
                coverURL: nil,
                musicURL: nil,
                posts: [],
                createdAt: Date()
            ),
            StoryCard(
                title: "旅行札记",
                author: "背包客",
                preview: "行走在路上的点点滴滴...",
                coverURL: nil,
                musicURL: nil,
                posts: [],
                createdAt: Date()
            )
        ]
    }
    
    private func generateMockMusic() -> [MusicRecommendation] {
        return [
            MusicRecommendation(
                title: "Summer Breeze",
                artist: "Chill Master",
                coverURL: "https://example.com/cover1.jpg",
                audioURL: "https://example.com/audio1.mp3",
                category: .chill,
                usageCount: 1250,
                isPopular: true
            ),
            MusicRecommendation(
                title: "City Lights",
                artist: "Urban Sound",
                coverURL: "https://example.com/cover2.jpg",
                audioURL: "https://example.com/audio2.mp3",
                category: .trending,
                usageCount: 2100,
                isPopular: true
            ),
            MusicRecommendation(
                title: "Morning Coffee",
                artist: "Acoustic Vibes",
                coverURL: "https://example.com/cover3.jpg",
                audioURL: "https://example.com/audio3.mp3",
                category: .study,
                usageCount: 890,
                isPopular: false
            )
        ]
    }
}

// MARK: - 模式选择按钮

struct ModeTabButton: View {
    let mode: DiscoverMode
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(mode.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: mode.gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected 
                            ? Color.clear 
                            : Color(.systemGray4),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: isSelected 
                    ? mode.gradient[0].opacity(0.3) 
                    : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 用户头像视图

struct UserAvatarView: View {
    let user: User
    let size: CGFloat
    
    var body: some View {
        Group {
            if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            Text(user.initials)
                                .font(.system(size: size * 0.4, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            } else {
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Text(user.initials)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .pink.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
    }
}

// MARK: - 时间指示器

struct TimeIndicatorView: View {
    @State private var currentTime = Date()
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .opacity(0.8)
            
            Text(currentTime, style: .time)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                currentTime = Date()
            }
        }
    }
}

// MARK: - 浮动几何形状

struct FloatingShape: View {
    let size: CGFloat
    let color: Color
    let offset: CGPoint
    let rotationSpeed: Double
    let scrollOffset: CGFloat
    
    @State private var rotation: Double = 0
    
    var body: some View {
        Group {
            if Bool.random() {
                Circle()
                    .fill(color)
            } else {
                RoundedRectangle(cornerRadius: size * 0.2)
                    .fill(color)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .position(
            x: offset.x,
            y: offset.y + scrollOffset * 0.1
        )
        .onAppear {
            withAnimation(.linear(duration: rotationSpeed).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - 滚动偏移偏好键

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    EnhancedDiscoverView()
}
