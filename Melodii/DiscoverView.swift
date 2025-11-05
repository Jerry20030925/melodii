//
//  DiscoverView.swift
//  Melodii
//
//  Created by Jianwei Chen on 30/10/2025.
//

import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import Combine

// MARK: - Feed Type

enum FeedType: String, CaseIterable {
    case recommended = "推荐"
    case following = "关注"
}

// MARK: - Paging State

private struct FeedPagingState<Item: Identifiable & Equatable> {
    var items: [Item] = []
    var isInitialLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var hasMore = true
    var nextOffset = 0
    let pageSize: Int = 20

    mutating func reset() {
        items = []
        isInitialLoading = false
        isRefreshing = false
        isLoadingMore = false
        hasMore = true
        nextOffset = 0
    }
}

struct DiscoverView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var selectedFeedType: FeedType = .recommended

    // 分页状态
    @State private var recommendedState = FeedPagingState<Post>()
    @State private var followingState = FeedPagingState<Post>()

    // 智能刷新：记录已查看的帖子ID
    @State private var viewedPostIds: Set<String> = []

    @State private var showError = false
    @State private var errorMessage = ""

    // 搜索相关
    @State private var isShowingSearch = false
    @State private var searchText = ""
    @State private var searchTab: Int = 0 // 0 内容 1 用户
    @State private var searchPostsState = FeedPagingState<Post>()
    @State private var searchUsersState = FeedPagingState<User>()
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchHistory: [String] = []
    // 防抖/可取消任务
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                // 渐变底图，衬托毛玻璃材质卡片
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.06),
                        Color.purple.opacity(0.06),
                        Color.cyan.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    FeedTypePicker(selectedType: $selectedFeedType)
                        .padding(.top, 8)

                    Divider()

                    feedScrollView
                }
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $isShowingSearch) {
                searchSheet
            }
            .task {
                if currentPosts.isEmpty {
                    await initialLoad()
                }
                await subscribeRealtimePosts()
            }
            .onChange(of: selectedFeedType) { _, _ in
                Task {
                    if currentPosts.isEmpty {
                        await initialLoad()
                    }
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadSearchHistory()
            }
            .navigationDestination(for: User.self) { user in
                UserProfileView(user: user)
            }
        } // closes NavigationStack
    }

    // MARK: - Split out the ScrollView to reduce type-checking complexity

    @State private var isRefreshing = false
    @State private var showMHeader = false
    @State private var pullProgress: CGFloat = 0

    private var feedScrollView: some View {
        ScrollViewReader { _ in
            ScrollView {
                feedListContent
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("feedScroll")).minY)
                        }
                    )
            }
            .coordinateSpace(name: "feedScroll")
            .refreshable {
                await MainActor.run { isRefreshing = true; showMHeader = true }
                await refreshWithRecommendations()
                await MainActor.run {
                    isRefreshing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showMHeader = false }
                }
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let offset = max(0, value)
                let progress = min(offset / 80.0, 1.0)
                pullProgress = progress
                showMHeader = isRefreshing || progress > 0.01
            }
            .safeAreaInset(edge: .top) {
                if showMHeader {
                    MRefreshHeader(isRefreshing: isRefreshing, progress: pullProgress)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: - List Content

    private var feedListContent: some View {
        let posts = currentPosts
        return Group {
            if isCurrentInitialLoading && posts.isEmpty {
                skeletonListView
            } else if posts.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        PostRow(post: post, index: index, totalCount: posts.count) {
                            Task { await loadMoreIfNeeded() }
                        }
                        .onAppear {
                            // 预加载即将显示的视频
                            preloadUpcomingVideos(currentIndex: index, posts: posts)
                        }
                    }

                    if isCurrentLoadingMore {
                        ProgressView()
                            .padding(.vertical, 16)
                            .transition(.opacity)
                    } else if !currentHasMore && !posts.isEmpty {
                        Text("没有更多了")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Refresh with "M" animation and recommendations

    private func refreshWithRecommendations() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // 先完全重置并刷新当前feed
        await MainActor.run {
            switch selectedFeedType {
            case .recommended:
                recommendedState.reset()
            case .following:
                followingState.reset()
            }
        }
        await refreshCurrentFeed()

        // 推荐3-5篇新帖子（使用随机offset来获取不同内容）
        let count = Int.random(in: 3...5)
        guard let uid = authService.currentUser?.id else { return }
        do {
            // 使用随机offset来避免总是获取相同的帖子
            let randomOffset = Int.random(in: 0...10)
            let recs = try await supabaseService.fetchRecommendedPosts(userId: uid, limit: count, offset: randomOffset)
            let existingIds = Set(currentPosts.map { $0.id })
            let newOnes = recs.filter { !existingIds.contains($0.id) }
            if !newOnes.isEmpty {
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        switch selectedFeedType {
                        case .recommended:
                            recommendedState.items.insert(contentsOf: newOnes, at: 0)
                        case .following:
                            followingState.items.insert(contentsOf: newOnes, at: 0)
                        }
                    }
                }
            }
        } catch {
            print("推荐内容加载失败: \(error)")
        }
    }
    
    /// 预加载即将显示的视频
    private func preloadUpcomingVideos(currentIndex: Int, posts: [Post]) {
        let preloadRange = 2 // 预加载前后2个帖子的视频
        let startIndex = max(0, currentIndex - preloadRange)
        let endIndex = min(posts.count - 1, currentIndex + preloadRange)
        
        for i in startIndex...endIndex {
            let post = posts[i]
            let videoURLs = post.mediaURLs.filter { $0.isVideoURL }
            VideoPreloadManager.shared.preloadVideos(urls: videoURLs)
        }
    }

    // MARK: - Realtime Posts Subscription

    private func subscribeRealtimePosts() async {
        await RealtimeFeedService.shared.subscribeToPosts { post in
            Task {
                // 仅处理已发布内容
                guard post.status == .published else { return }

                // 构建一个保证非可选的作者对象（Post.author 是非可选）
                var enriched = post
                let fetchedAuthor = try? await supabaseService.fetchUser(id: post.authorId)
                let finalAuthor = fetchedAuthor ?? User(id: post.authorId, nickname: "用户")
                enriched.author = finalAuthor

                await MainActor.run {
                    // 推荐流：插入顶部（避免重复）
                    if !recommendedState.items.contains(where: { $0.id == enriched.id }) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            recommendedState.items.insert(enriched, at: 0)
                        }
                    }
                }

                // 关注流：仅当我关注了作者时插入（异步检查，避免阻塞）
                if let uid = authService.currentUser?.id {
                    let isFollowing = (try? await supabaseService.isFollowing(followerId: uid, followingId: post.authorId)) ?? false
                    if isFollowing {
                        await MainActor.run {
                            if !followingState.items.contains(where: { $0.id == enriched.id }) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    followingState.items.insert(enriched, at: 0)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var currentPosts: [Post] {
        switch selectedFeedType {
        case .recommended:
            return recommendedState.items
        case .following:
            return followingState.items
        }
    }

    private var isCurrentInitialLoading: Bool {
        switch selectedFeedType {
        case .recommended: return recommendedState.isInitialLoading
        case .following: return followingState.isInitialLoading
        }
    }

    private var isCurrentLoadingMore: Bool {
        switch selectedFeedType {
        case .recommended: return recommendedState.isLoadingMore
        case .following: return followingState.isLoadingMore
        }
    }

    private var currentHasMore: Bool {
        switch selectedFeedType {
        case .recommended: return recommendedState.hasMore
        case .following: return followingState.hasMore
        }
    }

    // 骨架屏列表
    private var skeletonListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in
                    PostCardSkeleton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private var initialLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("加载中...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var emptyStateView: some View {
        Group {
            switch selectedFeedType {
            case .recommended:
                ContentUnavailableView(
                    "还没有内容",
                    systemImage: "sparkles",
                    description: Text("还没有人发布动态\n快来发布第一条吧！")
                )
            case .following:
                VStack(spacing: 20) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Text("还没有关注任何人")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("关注感兴趣的用户，查看他们的最新动态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        selectedFeedType = .recommended
                    } label: {
                        Text("去推荐页面看看")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                }
                .padding(40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - 搜索视图与逻辑
    // TODO: Replace placeholder searchSheet with your real search UI.
    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("搜索")
                    .font(.title3)
                TextField("搜索内容或用户", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { isShowingSearch = false }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func initialLoad() async {
        switch selectedFeedType {
        case .recommended:
            if recommendedState.isInitialLoading { return }
            await MainActor.run { recommendedState.isInitialLoading = true }
            defer { Task { @MainActor in recommendedState.isInitialLoading = false } }

            let limit = recommendedState.pageSize
            let offset = recommendedState.nextOffset
            do {
                let page = try await loadPage(for: .recommended, limit: limit, offset: offset)
                await MainActor.run {
                    recommendedState.items.append(contentsOf: page)
                    recommendedState.nextOffset += page.count
                    recommendedState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }

        case .following:
            if followingState.isInitialLoading { return }
            await MainActor.run { followingState.isInitialLoading = true }
            defer { Task { @MainActor in followingState.isInitialLoading = false } }

            guard authService.currentUser?.id != nil else {
                await MainActor.run {
                    followingState.items = []
                    followingState.hasMore = false
                }
                return
            }

            let limit = followingState.pageSize
            let offset = followingState.nextOffset
            do {
                let page = try await loadPage(for: .following, limit: limit, offset: offset)
                await MainActor.run {
                    followingState.items.append(contentsOf: page)
                    followingState.nextOffset += page.count
                    followingState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }
        }
    }

    private func refreshCurrentFeed() async {
        switch selectedFeedType {
        case .recommended:
            if recommendedState.isRefreshing { return }
            await MainActor.run {
                recommendedState.reset()
                recommendedState.isRefreshing = true
            }
            defer { Task { @MainActor in recommendedState.isRefreshing = false } }

            let limit = recommendedState.pageSize
            let offset = 0
            do {
                let page = try await loadPage(for: .recommended, limit: limit, offset: offset)
                await MainActor.run {
                    recommendedState.items = page
                    recommendedState.nextOffset = page.count
                    recommendedState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }

        case .following:
            if followingState.isRefreshing { return }
            await MainActor.run {
                followingState.reset()
                followingState.isRefreshing = true
            }
            defer { Task { @MainActor in followingState.isRefreshing = false } }

            guard authService.currentUser?.id != nil else {
                await MainActor.run {
                    followingState.items = []
                    followingState.hasMore = false
                }
                return
            }

            let limit = followingState.pageSize
            let offset = 0
            do {
                let page = try await loadPage(for: .following, limit: limit, offset: offset)
                await MainActor.run {
                    followingState.items = page
                    followingState.nextOffset = page.count
                    followingState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }
        }

        await MainActor.run {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func loadMoreIfNeeded() async {
        switch selectedFeedType {
        case .recommended:
            guard recommendedState.hasMore, !recommendedState.isLoadingMore else { return }
            await MainActor.run { recommendedState.isLoadingMore = true }
            defer { Task { @MainActor in recommendedState.isLoadingMore = false } }

            let limit = recommendedState.pageSize
            let offset = recommendedState.nextOffset
            do {
                let page = try await loadPage(for: .recommended, limit: limit, offset: offset)
                await MainActor.run {
                    recommendedState.items.append(contentsOf: page)
                    recommendedState.nextOffset += page.count
                    recommendedState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }

        case .following:
            guard followingState.hasMore, !followingState.isLoadingMore else { return }
            guard authService.currentUser?.id != nil else { return }
            await MainActor.run { followingState.isLoadingMore = true }
            defer { Task { @MainActor in followingState.isLoadingMore = false } }

            let limit = followingState.pageSize
            let offset = followingState.nextOffset
            do {
                let page = try await loadPage(for: .following, limit: limit, offset: offset)
                await MainActor.run {
                    followingState.items.append(contentsOf: page)
                    followingState.nextOffset += page.count
                    followingState.hasMore = page.count == limit
                }
            } catch {
                handleLoadError(error)
            }
        }
    }

    // Fetch a page without touching @State.
    private func loadPage(for feed: FeedType, limit: Int, offset: Int) async throws -> [Post] {
        switch feed {
        case .recommended:
            if let uid = authService.currentUser?.id {
                return try await supabaseService.fetchRecommendedPosts(userId: uid, limit: limit, offset: offset)
            } else {
                return try await supabaseService.fetchTrendingPosts(limit: limit, offset: offset)
            }
        case .following:
            guard let uid = authService.currentUser?.id else { return [] }
            return try await supabaseService.fetchFollowingPosts(userId: uid, limit: limit, offset: offset)
        }
    }

    private func handleLoadError(_ error: Error) {
        if (error as? CancellationError) != nil { return }
        Task { @MainActor in
            errorMessage = "加载失败: \(error.localizedDescription)"
            showError = true
        }
        print("❌ Discover 加载失败: \(error)")
    }

    private func loadSearchHistory() {
        // TODO: Replace with persistence. For now, keep it empty.
        searchHistory = []
    }
}

// MARK: - Feed Type Picker

private struct FeedTypePicker: View {
    @Binding var selectedType: FeedType

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FeedType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedType = type
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(type.rawValue)
                            .font(.headline)
                            .foregroundStyle(selectedType == type ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)

                        Rectangle()
                            .fill(selectedType == type ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Post Row (extracted to keep ForEach simple)

private struct PostRow: View {
    let post: Post
    let index: Int
    let totalCount: Int
    let onReachEnd: () -> Void

    var body: some View {
        PostCardView(post: post)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index % 10) * 0.05), value: totalCount)
            .onAppear {
                onAppearIfLast()
            }
    }

    private func onAppearIfLast() {
        onReachEndIfNeeded()
    }

    private func onReachEndIfNeeded() {
        onReachEnd()
    }
}

// MARK: - Post Card View

struct PostCardView: View {
    let post: Post
    var enableImageViewer: Bool = true

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var isLiked = false
    @State private var likeCount: Int
    @State private var isAnimatingLike = false
    @State private var isTogglingLike = false
    @State private var isCollected = false
    @State private var collectCount: Int = 0
    @State private var isTogglingCollect = false

    // 全屏媒体预览
    @State private var showMediaViewer = false
    @State private var mediaViewerIndex = 0
    @State private var appeared = false

    init(post: Post, enableImageViewer: Bool = true) {
        self.post = post
        self.enableImageViewer = enableImageViewer
        _likeCount = State(initialValue: post.likeCount)
    }

    @State private var showPostDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 作者信息 + 操作
            HStack(spacing: 12) {
                NavigationLink(destination: UserProfileView(user: post.author)) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: post.isAnonymous ? [.gray.opacity(0.6), .gray.opacity(0.8)] : [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(post.isAnonymous ? "匿" : post.author.initials)
                                .font(.headline)
                                .foregroundStyle(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .disabled(post.isAnonymous)

                NavigationLink(destination: UserProfileView(user: post.author)) {
                    VStack(alignment: .leading, spacing: 2) {
                        // 匿名帖子显示"匿名"，非匿名帖子显示真实昵称
                        let displayName = post.isAnonymous ? "匿名" : post.author.nickname
                        Text(displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            // 匿名帖子不显示MID
                            if !post.isAnonymous {
                                if let mid = post.author.mid, !mid.isEmpty {
                                    Text("@\(mid)")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("@\(post.author.id.prefix(8))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("@匿名用户")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            Text(post.createdAt.timeAgoDisplay)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                
                            if let city = post.city, !city.isEmpty {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                
                                Text(city)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                NavigationLink {
                    PostDetailView(post: post)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
            }
            .padding(16)

            // 媒体区域：支持内联视频（静音预览，点击进入详情开启声音）与图片混排
            if !post.mediaURLs.isEmpty {
                let isSingleVideo = (post.mediaURLs.count == 1) && (post.mediaURLs.first?.isVideoURL == true)
                Group {
                    if isSingleVideo {
                        // 单视频：外部卡片只做静音预览，点击进入详情页播放完整视频（含声音）
                        NavigationLink(destination: PostDetailView(post: post)) {
                            MediaGridForPost(
                                urls: post.mediaURLs,
                                enableViewer: false,
                                onTap: { _ in }
                            )
                            .aspectRatio(mediaAspectRatio(for: post.mediaURLs.count), contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: PostDetailView(post: post)) {
                            MediaGridForPost(
                                urls: post.mediaURLs,
                                enableViewer: false,
                                onTap: { _ in }
                            )
                            .aspectRatio(mediaAspectRatio(for: post.mediaURLs.count), contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipped()
                .overlay(Color.clear)
                .zIndex(0)
            }

            if let text = post.text, !text.isEmpty {
                NavigationLink {
                    PostDetailView(post: post)
                } label: {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .padding(.horizontal, 16)
                        .padding(.top, post.mediaURLs.isEmpty ? 0 : 12)
                        .padding(.bottom, 12)
                }
                .buttonStyle(.plain)
            }

            if !post.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.topics, id: \.self) { topic in
                            Text("#\(topic)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked ? .red : .primary)
                        .scaleEffect(isAnimatingLike ? 1.3 : 1.0)
                        .symbolEffect(.bounce, value: isLiked)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isTogglingLike)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimatingLike)

                Color(.systemGray5)
                    .frame(width: 1, height: 20)

                NavigationLink { PostDetailView(post: post) } label: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Color(.systemGray5)
                    .frame(width: 1, height: 20)

                Button {
                    Task { await toggleCollect() }
                } label: {
                    Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(isCollected ? .blue : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isTogglingCollect)
            }
            .contentShape(Rectangle())
            .zIndex(1)
            .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(appeared ? 0.08 : 0), radius: appeared ? 12 : 0, x: 0, y: appeared ? 4 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color(.systemGray6).opacity(0.5), Color(.systemGray5).opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)
        .task {
            await loadLikeStatus()
            await loadCollectStatus()
        }
        .onAppear {
            withAnimation {
                appeared = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showPostDetail = true
        }
        .background(
            NavigationLink(destination: PostDetailView(post: post), isActive: $showPostDetail) {
                EmptyView()
            }
            .hidden()
        )
    }

    private func mediaAspectRatio(for count: Int) -> CGFloat {
        if count == 1 { return 4.0/3.0 }
        if count == 2 { return 1.2 }
        if count == 3 { return 1.2 }
        return 1.2
    }

    private func loadLikeStatus() async {
        guard let userId = authService.currentUser?.id else { return }
        do {
            isLiked = try await supabaseService.hasLikedPost(userId: userId, postId: post.id)
        } catch {
            print("加载点赞状态失败: \(error)")
        }
    }

    private func loadCollectStatus() async {
        guard let userId = authService.currentUser?.id else { return }
        do {
            isCollected = try await supabaseService.hasCollectedPost(userId: userId, postId: post.id)
        } catch {
            print("加载收藏状态失败: \(error)")
        }
    }

    private func toggleLike() async {
        guard let userId = authService.currentUser?.id else { return }

        isTogglingLike = true
        let wasLiked = isLiked
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        if isLiked {
            isAnimatingLike = true
        }

        do {
            if isLiked {
                try await supabaseService.likePost(userId: userId, postId: post.id)
                await MainActor.run { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            } else {
                try await supabaseService.unlikePost(userId: userId, postId: post.id)
                await MainActor.run { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        } catch {
            isLiked = wasLiked
            likeCount += wasLiked ? 1 : -1
            await MainActor.run { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            print("点赞操作失败: \(error)")
        }

        if isLiked {
            try? await Task.sleep(nanoseconds: 300_000_000)
            isAnimatingLike = false
        }
        isTogglingLike = false
    }

    private func toggleCollect() async {
        guard let userId = authService.currentUser?.id else { return }

        isTogglingCollect = true
        let wasCollected = isCollected
        isCollected.toggle()
        collectCount += isCollected ? 1 : -1

        do {
            if isCollected {
                try await supabaseService.collectPost(userId: userId, postId: post.id)
                await MainActor.run { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            } else {
                try await supabaseService.uncollectPost(userId: userId, postId: post.id)
                await MainActor.run { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
        } catch {
            isCollected = wasCollected
            collectCount += wasCollected ? 1 : -1
            await MainActor.run { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            print("收藏操作失败: \(error)")
        }

        isTogglingCollect = false
    }
}

// MARK: - Media Grid For Post (图片/视频混排 + 单视频内联播放)

private struct MediaGridForPost: View {
    let urls: [String]
    var enableViewer: Bool
    var onTap: ((Int) -> Void)?

    private func isVideo(_ url: String) -> Bool {
        return url.isVideoURL
    }

    var body: some View {
        let spacing: CGFloat = 3

        if urls.count == 1 {
            let url = urls[0]
            if isVideo(url) {
                // 单视频：内联播放
                VideoInlinePlayer(urlString: url)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                single(url, index: 0)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else if urls.count == 2 {
            HStack(spacing: spacing) {
                ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                    mediaTile(url, index: idx)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 200)
        } else if urls.count == 3 {
            HStack(spacing: spacing) {
                mediaTile(urls[0], index: 0)
                    .frame(maxWidth: .infinity)
                VStack(spacing: spacing) {
                    mediaTile(urls[1], index: 1)
                        .frame(maxHeight: .infinity)
                    mediaTile(urls[2], index: 2)
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 280)
        } else {
            let firstFour = Array(urls.prefix(4))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing),
                                GridItem(.flexible(), spacing: spacing)], spacing: spacing) {
                ForEach(Array(firstFour.enumerated()), id: \.offset) { index, url in
                    ZStack {
                        mediaTile(url, index: index)
                        if index == 3 && urls.count > 4 {
                            Color.black.opacity(0.35)
                            Text("+\(urls.count - 4)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    private func mediaTile(_ url: String, index: Int) -> some View {
        Group {
            if isVideo(url) {
                VideoThumbnailView(urlString: url)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?(index) }
            } else {
                square(url, index: index)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func single(_ url: String, index: Int) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
                Rectangle().fill(Color(.systemGray6)).overlay(ProgressView())
            case .success(let image):
                image.resizable().scaledToFill()
                    .onTapGesture { onTap?(index) }
            case .failure:
                Rectangle().fill(Color(.systemGray6)).overlay(Image(systemName: "photo"))
            @unknown default: EmptyView()
            }
        }
        .aspectRatio(4/3, contentMode: .fill)
        .contentShape(Rectangle())
    }

    private func square(_ url: String, index: Int) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .empty:
                Rectangle().fill(Color(.systemGray6)).overlay(ProgressView())
            case .success(let image):
                image.resizable().scaledToFill()
                    .onTapGesture { onTap?(index) }
            case .failure:
                Rectangle().fill(Color(.systemGray6)).overlay(Image(systemName: "photo"))
            @unknown default: EmptyView()
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .contentShape(Rectangle())
        .clipped()
    }
}

// MARK: - 优化的内联播放器（静音、循环、出现即播、离开即停）

private struct VideoInlinePlayer: View {
    let urlString: String
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.2)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
            } else if hasError {
                Rectangle().fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text("视频加载失败")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("重试") {
                                setupAndPlay()
                            }
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        }
                    )
            } else if isLoading {
                Rectangle().fill(Color.black)
                    .overlay(
                        VStack(spacing: 6) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("加载中...")
                                .font(.caption2)
                                .foregroundStyle(.white)
                        }
                    )
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            setupAndPlay()
        }
        .onDisappear {
            teardown()
        }
    }

    private func setupAndPlay() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        isLoading = true
        hasError = false
        
        // 清理之前的播放器
        teardown()
        
        // 尝试使用预加载的播放器
        if let (queuePlayer, playerLooper) = VideoPreloadManager.shared.createOptimizedQueuePlayer(url: urlString) {
            queuePlayer.isMuted = true
            queuePlayer.actionAtItemEnd = .none
            self.player = queuePlayer
            self.looper = playerLooper
            isLoading = false
            hasError = false
            queuePlayer.play()
            return
        }
        
        // 创建新的播放器项目
        let item = AVPlayerItem(url: url)
        
        // 监听播放器状态
        item.publisher(for: \.status)
            .sink { status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        isLoading = false
                        hasError = false
                        
                        // 仅当未初始化时创建，避免重复
                        if player == nil {
                            let queue = AVQueuePlayer(items: [item])
                            queue.isMuted = true
                            queue.actionAtItemEnd = .none
                            let loop = AVPlayerLooper(player: queue, templateItem: item)
                            self.player = queue
                            self.looper = loop
                            queue.play()
                        }
                    case .failed:
                        isLoading = false
                        hasError = true
                        print("内联视频播放失败: \(item.error?.localizedDescription ?? "未知错误")")
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func teardown() {
        player?.pause()
        player?.removeAllItems()
        player = nil
        looper = nil
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Lightweight Skeleton (placeholder)

private struct PostCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 180, height: 10)
                }
                Spacer()
            }
            .padding(16)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(height: 180)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 1)
                .padding(.horizontal, 16)

            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 24)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 24)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 80, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Video Thumbnail View

private struct VideoThumbnailView: View {
    let urlString: String
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()

                // 播放按钮覆盖层
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
            } else if hasError {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("无法加载")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else if isLoading {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }

        Task.detached(priority: .background) {
            do {
                let asset = AVURLAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 400, height: 400)

                let time = CMTime(seconds: 0, preferredTimescale: 600)
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage)

                await MainActor.run {
                    thumbnail = image
                    isLoading = false
                }
            } catch {
                print("❌ 视频缩略图生成失败: \(error)")
                await MainActor.run {
                    hasError = true
                    isLoading = false
                }
            }
        }
    }
}
// MARK: - M Refresh Header

private struct MRefreshHeader: View {
    let isRefreshing: Bool
    let progress: CGFloat // 下拉进度 0~1
    @State private var anim: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let width: CGFloat = 28
                let height: CGFloat = 16
                let startX: CGFloat = geo.size.width / 2 - width / 2
                let startY: CGFloat = 6

                // 构建“M”路径
                let path: Path = {
                    var p = Path()
                    p.move(to: CGPoint(x: startX, y: startY + height))
                    p.addLine(to: CGPoint(x: startX, y: startY))
                    p.addLine(to: CGPoint(x: startX + width/2, y: startY + height/2))
                    p.addLine(to: CGPoint(x: startX + width, y: startY))
                    p.addLine(to: CGPoint(x: startX + width, y: startY + height))
                    return p
                }()

                // 更顺滑的动态渐变：色相与起止点随时间轻微漂移
                let hue1 = (sin(t * 1.2) * 0.5 + 0.5)
                let hue2 = (sin(t * 1.2 + 1.0) * 0.5 + 0.5)
                let startShift = 0.2 + 0.3 * (sin(t * 1.0) * 0.5 + 0.5)
                let endShift = 0.8 - startShift
                let gradient = LinearGradient(
                    colors: [Color(hue: hue1, saturation: 0.9, brightness: 1.0),
                             Color(hue: hue2, saturation: 0.9, brightness: 1.0)],
                    startPoint: UnitPoint(x: startShift, y: 0),
                    endPoint: UnitPoint(x: endShift, y: 1)
                )

                // 动态路径表现：刷新中用流动虚线；未刷新时做一次性描边
                let dashPhase = isRefreshing ? CGFloat(t * 60).truncatingRemainder(dividingBy: 1000) : 0
                path
                    .trim(from: 0, to: isRefreshing ? 1 : anim)
                    .stroke(
                        gradient,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: isRefreshing ? [8, 6] : [],
                            dashPhase: dashPhase
                        )
                    )
                    .frame(height: height + 8)
                    .onChange(of: isRefreshing) { _, refreshing in
                        if refreshing { withAnimation(.easeInOut(duration: 0.25)) { anim = 1 } }
                        else { withAnimation(.easeInOut(duration: 0.25)) { anim = 0 } }
                    }
                    .onChange(of: progress) { _, p in
                        if !isRefreshing {
                            withAnimation(.easeOut(duration: 0.12)) { anim = max(0, min(1, p)) }
                        }
                    }
            }
        }
        .frame(height: 32)
    }
}

// 读取滚动偏移的偏好键（供外层自定义下拉用）
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
