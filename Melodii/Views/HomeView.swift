//
//  HomeView.swift
//  Melodii
//
//  Home feed with gentle, stress-free design
//

import SwiftUI

struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared

    @State private var selectedFeed: FeedType = .recommended
    @State private var posts: [Post] = []
    @State private var isLoading = false              // 首次加载指示
    @State private var isRefreshing = false           // 下拉刷新状态
    @State private var isPageLoading = false          // 串行化分页加载
    @State private var hasMore = true
    @State private var nextOffset = 0
    private let pageSize = 20

    // 智能刷新：记录已查看的帖子ID
    @State private var viewedPostIds: Set<String> = []

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSearch = false
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部 Header
                    headerView
                        .padding(Edge.Set.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    // Feed 类型切换
                    feedTypePicker
                        .padding(Edge.Set.horizontal, 16)
                        .padding(.bottom, 20)

                    // Feed 内容
                    if posts.isEmpty && !isLoading {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                                PostCardView(post: post)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index % 10) * 0.05), value: posts.count)
                                    .onAppear {
                                        if post == posts.last {
                                            Task { await loadMore() }
                                        }
                                    }
                            }

                            if hasMore {
                                ProgressView()
                                    .padding(.vertical, 20)
                                    .transition(.opacity)
                            } else if !posts.isEmpty {
                                Text("已经到底啦 ✨")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 20)
                                    .transition(.opacity)
                            }
                        }
                        .padding(Edge.Set.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }

                // 替换为通知按钮（带未读红点）
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .foregroundStyle(.secondary)
                            if unreadCenter.unreadNotifications > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 6, y: -6)
                                    .transition(.scale)
                            }
                        }
                    }
                    .accessibilityLabel("通知")
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
            // 展示通知列表（使用你项目里已有的 NotificationsView）
            .sheet(isPresented: $showNotifications, onDismiss: {
                Task { await refreshUnreadNotifications() }
            }) {
                NavigationStack {
                    NotificationsView()
                        .navigationTitle("通知")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") { showNotifications = false }
                            }
                        }
                }
            }
        }
        .task {
            if posts.isEmpty {
                await initialLoad()
            }
            await refreshUnreadNotifications()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .navigationDestination(for: User.self) { user in
            UserProfileView(user: user)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Melodii")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("让每个普通瞬间，都值得被看见")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feed Type Picker

    private var feedTypePicker: some View {
        HStack(spacing: 0) {
            // 推荐 Tab
            Button {
                if selectedFeed != .recommended {
                    selectedFeed = .recommended
                    Task { await refresh() }
                }
            } label: {
                VStack(spacing: 8) {
                    Text("推荐")
                        .font(.subheadline)
                        .fontWeight(selectedFeed == .recommended ? .semibold : .regular)
                        .foregroundStyle(selectedFeed == .recommended ? .primary : .secondary)

                    if selectedFeed == .recommended {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // 关注 Tab
            Button {
                if selectedFeed != .following {
                    selectedFeed = .following
                    Task { await refresh() }
                }
            } label: {
                VStack(spacing: 8) {
                    Text("关注")
                        .font(.subheadline)
                        .fontWeight(selectedFeed == .following ? .semibold : .regular)
                        .foregroundStyle(selectedFeed == .following ? .primary : .secondary)

                    if selectedFeed == .following {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("还没有动态")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("快来分享你的生活瞬间吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Data Loading

    private func initialLoad() async {
        isLoading = true
        _ = await loadPage()
        isLoading = false
    }

    private func refresh() async {
        if isPageLoading {
            while isPageLoading { try? await Task.sleep(nanoseconds: 50_000_000) }
        }

        isRefreshing = true

        // 暂存旧数据，刷新失败时恢复
        let oldPosts = posts
        let oldOffset = nextOffset
        let oldHasMore = hasMore

        posts = []
        nextOffset = 0
        hasMore = true

        if selectedFeed == .following && authService.currentUser?.id == nil {
            posts = oldPosts
            nextOffset = oldOffset
            hasMore = oldHasMore
            isRefreshing = false
            return
        }

        let success = await loadPage()

        // 如果刷新失败且没有新数据，恢复旧数据
        if !success && posts.isEmpty {
            posts = oldPosts
            nextOffset = oldOffset
            hasMore = oldHasMore
        }

        isRefreshing = false

        // 只在成功时给用户反馈
        if success {
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !isPageLoading else { return }
        _ = await loadPage()
    }

    @discardableResult
    private func loadPage() async -> Bool {
        guard !isPageLoading else { return false }
        isPageLoading = true
        defer { isPageLoading = false }

        do {
            let page: [Post]
            switch selectedFeed {
            case .recommended:
                if let userId = authService.currentUser?.id {
                    page = try await supabaseService.fetchRecommendedPosts(userId: userId, limit: pageSize, offset: nextOffset)
                } else {
                    page = try await supabaseService.fetchTrendingPosts(limit: pageSize, offset: nextOffset)
                }
            case .following:
                guard let userId = authService.currentUser?.id else {
                    hasMore = false
                    return false
                }
                page = try await supabaseService.fetchFollowingPosts(userId: userId, limit: pageSize, offset: nextOffset)
            }

            posts.append(contentsOf: page)
            nextOffset += page.count
            hasMore = page.count == pageSize
            return true
        } catch {
            if (error as? CancellationError) != nil { return false }

            // 只在非刷新状态时显示错误
            if !isRefreshing {
                errorMessage = "加载失败: \(error.localizedDescription)"
                showError = true
            }
            print("❌ 加载主页动态失败: \(error)")
            return false
        }
    }

    // MARK: - Notifications

    private func refreshUnreadNotifications() async {
        guard let userId = authService.currentUser?.id else {
            unreadCenter.unreadNotifications = 0
            return
        }
        if let count = try? await supabaseService.fetchUnreadNotificationCount(userId: userId) {
            unreadCenter.unreadNotifications = count
        }
    }
}

// 其余 GentlePostCard / TagView / RecommendationCardView / PostImagesView 与之前一致，已保留。
