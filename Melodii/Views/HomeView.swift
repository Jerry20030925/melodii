//
//  HomeView.swift
//  Melodii
//
//  Home feed with gentle, stress-free design
//

import SwiftUI
import PhotosUI

struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared

    @State private var selectedFeed: FeedType = .recommended
    @State private var posts: [Post] = []
    @State private var isLoading = false              // 首次加载指示
    @State private var isRefreshing = false           // 下拉刷新状态
    @State private var showMHeader = false            // 顶部“M”动画显示
    @State private var pullProgress: CGFloat = 0      // 下拉进度 0~1
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
    // MARK: - Melomoment 状态（迁移至 Moment 模型）
    @State private var melomoments: [Moment] = []
    @State private var isLoadingMoments = false
    @State private var melomomentPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingMoment = false
    @State private var recentMomentId: String? = nil
    // 新：添加按钮涟漪与导航到创作页
    @State private var showCreateMelomoment = false
    @State private var addRippleProgress: CGFloat = 0
    @State private var showAddRipple: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部 Header
                    headerView
                        .padding(Edge.Set.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    // 顶部 Melomoment 区域
                    melomomentBar
                        .padding(Edge.Set.horizontal, 16)
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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("homeScroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "homeScroll")
            .refreshable {
                await MainActor.run { isRefreshing = true; showMHeader = true }
                await refresh()
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
                    HomeRefreshHeader(isRefreshing: isRefreshing, progress: pullProgress)
                        .padding(.top, 6)
                }
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
            // 打开创作页（默认 Melomoment 模式）
            .sheet(isPresented: $showCreateMelomoment) {
                NavigationStack {
                    CreateView(draftPost: nil, initialMode: .melomoment)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") { showCreateMelomoment = false }
                            }
                        }
                }
            }
        }
        .task {
            if posts.isEmpty {
                await initialLoad()
            }
            // 加载互关的 Melomoment
            await loadMelomoments()
            // 实时订阅新帖子插入
            await subscribeRealtimePosts()
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

    // MARK: - Enhanced Melomoment Section with Premium Visual Effects
    private var melomomentBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with animated gradient title and enhanced upload button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Melomoment")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.2), radius: 2, x: 0, y: 2)
                    
                    Text("分享此刻")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                }
                
                Spacer()
                
                // 同款风格添加按钮：渐变环 + 涟漪，改为进入创作页
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    // 涟漪动画
                    showAddRipple = true
                    addRippleProgress = 0
                    withAnimation(.easeOut(duration: 0.6)) { addRippleProgress = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showAddRipple = false
                        addRippleProgress = 0
                    }
                    // 打开创作页并预选 Melomoment 模式
                    showCreateMelomoment = true
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            // 外环：彩虹渐变环
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [.pink, .orange, .purple, .blue, .cyan, .pink],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(270)
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 26, height: 26)

                            // 内圆：渐变填充
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.85), .pink.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 24, height: 24)

                            Image(systemName: "camera.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)

                            // 涟漪效果
                            if showAddRipple {
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.pink.opacity(0.9), .purple.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                    .frame(width: 24, height: 24)
                                    .scaleEffect(1 + addRippleProgress * 0.5)
                                    .opacity(1 - addRippleProgress)
                            }
                        }

                        Text("添加")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.1), .pink.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.3), .pink.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .accessibilityLabel("添加 Melomoment")
            }

            // Content area with enhanced loading and empty states
            Group {
                if isLoadingMoments {
                    HStack(spacing: 12) {
                        ForEach(Array(0..<3), id: \.self) { _ in
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 110, height: 110)
                                    .opacity(0.6)
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(width: 60, height: 12)
                                    .opacity(0.4)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if melomoments.isEmpty {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.1), .pink.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.6), .pink.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 4) {
                            Text("还没有 Melomoment")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.8))
                            
                            Text("分享你的精彩瞬间给朋友们")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    // Enhanced scroll view with improved animations
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(melomoments.enumerated()), id: \.element.id) { index, moment in
                                MelomomentCard(
                                    moment: moment,
                                    isHighlighted: recentMomentId == moment.id
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .trailing)
                                            .combined(with: .scale(scale: 0.8))
                                            .combined(with: .opacity),
                                        removal: .move(edge: .leading)
                                            .combined(with: .scale(scale: 0.8))
                                            .combined(with: .opacity)
                                    )
                                )
                                .animation(
                                    .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.1)
                                    .delay(Double(index) * 0.05),
                                    value: melomoments
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    .coordinateSpace(name: "melomomentScroll")
                    .ifAvailableIOS16 { $0.scrollBounceBehavior(.basedOnSize) }
                    .ifAvailableIOS17 { $0.scrollTargetBehavior(.viewAligned) }
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isLoadingMoments)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: melomoments.isEmpty)
        }
        .padding(.horizontal, 4)
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

    // MARK: - Melomoment 加载与上传
    private func loadMelomoments() async {
        guard !isLoadingMoments else { return }
        guard let myId = authService.currentUser?.id else { return }
        isLoadingMoments = true
        defer { isLoadingMoments = false }
        do {
            let moments = try await supabaseService.fetchMoments(userId: myId, limit: 30)
            await MainActor.run { melomoments = moments }
        } catch {
            print("❌ 加载 Melomoment 失败: \(error)")
        }
    }

    private func handlePickMelomoment(_ item: PhotosPickerItem?) async {
        guard !isUploadingMoment, let item else { return }
        guard let me = authService.currentUser?.id else { return }
        isUploadingMoment = true
        defer { isUploadingMoment = false }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let mime = "image/jpeg"
                let url = try await supabaseService.uploadUserMedia(
                    data: data,
                    mime: mime,
                    fileName: nil,
                    folder: "moments/\(me)"
                )

                let moment = try await supabaseService.createMoment(
                    authorId: me,
                    mediaURL: url,
                    caption: nil
                )

                await MainActor.run {
                    melomoments.insert(moment, at: 0)
                    recentMomentId = moment.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { recentMomentId = nil }
                }
            }
        } catch {
            print("❌ 上传 Melomoment 失败: \(error)")
        }
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
                    page = try await supabaseService.fetchTrendingPosts(limit: pageSize)
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

    // MARK: - Realtime Posts Subscription

    private func subscribeRealtimePosts() async {
        await RealtimeFeedService.shared.subscribeToPosts { post in
            Task { @MainActor in
                guard post.status == .published else { return }
                let author = (try? await supabaseService.fetchUser(id: post.authorId)) ?? User(id: post.authorId, nickname: "用户")
                var enriched = post
                enriched.author = author

                switch selectedFeed {
                case .recommended:
                    let myId = authService.currentUser?.id
                    if myId == nil || enriched.authorId != myId! {
                        if !posts.contains(where: { $0.id == enriched.id }) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                posts.insert(enriched, at: 0)
                            }
                        }
                    }
                case .following:
                    if !posts.contains(where: { $0.id == enriched.id }) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            posts.insert(enriched, at: 0)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Melomoment Card with Unique Visual Effects
struct MelomomentCard: View {
    let moment: Moment
    var isHighlighted: Bool = false
    @State private var appeared = false
    @State private var pressed = false
    @State private var hovered = false
    @State private var animationPhase: CGFloat = 0
    @State private var glowIntensity: CGFloat = 0
    @State private var particleOffset: CGFloat = 0
    @State private var rippleProgress: CGFloat = 0
    @State private var showRipple: Bool = false

    var body: some View {
        GeometryReader { geo in
            // Make types explicit to help the type checker
            let screenMidX: CGFloat = UIScreen.main.bounds.midX
            let midX: CGFloat = geo.frame(in: .global).midX
            let delta: CGFloat = midX - screenMidX
            let proximityFactor: CGFloat = 1.0 - min(abs(delta) / 200.0, 1.0)
            let computed = calculateTransformations(delta: delta, proximityFactor: proximityFactor)

            melomomentContent
                .frame(width: 110, height: 150)
                .rotation3DEffect(
                    .degrees(computed.tilt),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.5
                )
                .scaleEffect(computed.scale)
                .shadow(
                    color: isHighlighted
                        ? .purple.opacity(0.4)
                        : .black.opacity(computed.shadowOpacity),
                    radius: computed.shadowRadius,
                    x: computed.shadowX,
                    y: computed.shadowY
                )
                .opacity(appeared ? 1 : 0)
                .blur(radius: appeared ? 0 : 2)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
                        appeared = true
                    }
                    startAnimations()
                }
                .onTapGesture {
                    performTapFeedback()
                }
                .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { isPressing in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        pressed = isPressing
                    }
                    if isPressing {
                        performPressureFeedback()
                    }
                }, perform: {})
                .ifAvailableIOS17 { $0.sensoryFeedback(.impact(weight: .light), trigger: pressed) }
        }
        .frame(width: 110, height: 150)
    }

    // Split out the main content to simplify the body
    private var melomomentContent: some View {
        ZStack(alignment: .topLeading) {
            backgroundGradient

            VStack(alignment: .leading, spacing: 0) {
                imageContainer
                authorInfo
                    .padding(.top, 8)
            }

            if isHighlighted {
                floatingHeart
            }
        }
    }

    private var imageContainer: some View {
        ZStack {
            // 呼吸光晕（常显，突出焦点）
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(isHighlighted ? 0.20 : 0.12),
                            Color.pink.opacity(isHighlighted ? 0.14 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70
                    )
                )
                .frame(width: 130, height: 130)
                .scaleEffect(1 + glowIntensity * 0.06)
                .blur(radius: isHighlighted ? 8 : 6)

            // 彩虹环（常显；高亮时更粗且动态旋转）
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.pink, .orange, .purple, .blue, .cyan, .pink],
                        center: .center,
                        startAngle: .degrees(Double(animationPhase) * (isHighlighted ? 360.0 : 180.0)),
                        endAngle: .degrees(Double(animationPhase) * (isHighlighted ? 360.0 : 180.0) + 270.0)
                    ),
                    lineWidth: isHighlighted ? 3 : 2
                )
                .frame(width: 118, height: 118)
                .opacity(isHighlighted ? 0.9 : 0.6)
                .blur(radius: isHighlighted ? 0.6 : 0.4)

            AsyncImage(url: URL(string: moment.mediaURL)) { phase in
                switch phase {
                case .empty:
                    shimmerPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                case .failure:
                    failureView
                @unknown default:
                    shimmerPlaceholder
                }
            }
            .frame(width: 110, height: 110)

            if isHighlighted {
                particleRing
            }

            // 点击涟漪效果（渐扩圆环）
            if showRipple {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.pink.opacity(0.9), .purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 110, height: 110)
                    .scaleEffect(1 + rippleProgress * 0.5)
                    .opacity(1 - rippleProgress)
            }
        }
    }

    private var particleRing: some View {
        ZStack {
            ForEach(Array(0..<6), id: \.self) { index in
                let angle = Double(index) * .pi / 3 + Double(particleOffset)
                let x = CGFloat(cos(angle)) * 45
                let y = CGFloat(sin(angle)) * 45
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 4, height: 4)
                    .offset(x: x, y: y)
                    .opacity(0.7)
                    .blur(radius: 1)
            }
        }
    }

    private var authorInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(moment.author.nickname)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .lineLimit(1)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

            HStack(spacing: 2) {
                ForEach(Array(0..<3), id: \.self) { index in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 3, height: 3)
                        .opacity(isHighlighted ? 1 : 0.3)
                        .scaleEffect(
                            isHighlighted
                            ? (sin(animationPhase * 6 + Double(index) * 0.5) * 0.3 + 0.7)
                            : 0.5
                        )
                }

                Text(relativeTimeText(from: moment.createdAt))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .opacity(isHighlighted ? 1 : 0)
        }
    }

    private var floatingHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 10))
            .foregroundStyle(.pink)
            .opacity(0.8)
            .offset(
                x: CGFloat(cos(animationPhase * 4)) * 15 + 90,
                y: CGFloat(sin(animationPhase * 4)) * 10 + 20
            )
            .scaleEffect(sin(animationPhase * 8) * 0.3 + 0.7)
    }
    
    private var backgroundGradient: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: isHighlighted 
                        ? [.purple.opacity(0.15), .pink.opacity(0.1), .blue.opacity(0.05)]
                        : [.clear, .gray.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: isHighlighted
                                ? [.purple.opacity(0.3), .pink.opacity(0.2)]
                                : [.gray.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    private var shimmerPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 110, height: 110)
            .overlay(
                Circle()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
    }
    
    private var failureView: some View {
        Circle()
            .fill(Color.red.opacity(0.1))
            .frame(width: 110, height: 110)
            .overlay(
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red.opacity(0.6))
                    .font(.title2)
            )
    }
    
    private func calculateTransformations(delta: CGFloat, proximityFactor: CGFloat) -> (scale: CGFloat, tilt: Double, shadowOpacity: CGFloat, shadowRadius: CGFloat, shadowX: CGFloat, shadowY: CGFloat) {
        let baseScale: CGFloat = 0.95 + 0.1 * proximityFactor
        let pressedScale: CGFloat = pressed ? 0.92 : 1.0
        let highlightScale: CGFloat = isHighlighted ? 1.05 : 1.0
        let finalScale: CGFloat = baseScale * pressedScale * highlightScale * (appeared ? 1.0 : 0.9)
        
        let tilt: Double = max(-12.0, min(12.0, -Double(delta) / 15.0))
        
        let shadowOpacity: CGFloat = 0.15 + 0.1 * proximityFactor
        let shadowRadius: CGFloat = 8 + 6 * proximityFactor
        let shadowX: CGFloat = CGFloat(tilt) * 0.3
        let shadowY: CGFloat = 4 + 4 * proximityFactor
        
        return (finalScale, tilt, shadowOpacity, shadowRadius, shadowX, shadowY)
    }
    
    private func startAnimations() {
        // Continuous animation for highlighted state
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
        
        // Particle animation
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            particleOffset = .pi * 2
        }
        
        // Glow pulse
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            glowIntensity = 1.0
        }
    }

    private func performTapFeedback() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Visual feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            pressed = true
        }
        
        // Ripple animation
        showRipple = true
        rippleProgress = 0
        withAnimation(.easeOut(duration: 0.6)) {
            rippleProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showRipple = false
            rippleProgress = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                pressed = false
            }
        }
    }
    
    private func performPressureFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }

    private func relativeTimeText(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        return "\(days) 天前"
    }
}

// MARK: - 兼容性工具（便捷添加 iOS 版本可用的修饰符）
private extension View {
    @ViewBuilder
    func ifAvailableIOS16(apply: (Self) -> some View) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            apply(self)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func ifAvailableIOS17(apply: (Self) -> some View) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            apply(self)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// 顶部“M”动画（Home 专用）
private struct HomeRefreshHeader: View {
    let isRefreshing: Bool
    let progress: CGFloat
    @State private var anim: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let width: CGFloat = 28
                let height: CGFloat = 16
                let startX: CGFloat = geo.size.width / 2 - width / 2
                let startY: CGFloat = 6

                // 构建“M”路径为局部常量，确保返回单一 View 类型
                let path: Path = {
                    var p = Path()
                    p.move(to: CGPoint(x: startX, y: startY + height))
                    p.addLine(to: CGPoint(x: startX, y: startY))
                    p.addLine(to: CGPoint(x: startX + width/2, y: startY + height/2))
                    p.addLine(to: CGPoint(x: startX + width, y: startY))
                    p.addLine(to: CGPoint(x: startX + width, y: startY + height))
                    return p
                }()

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

                let dashPhase = isRefreshing ? CGFloat(t * 60).truncatingRemainder(dividingBy: 1000) : 0
                path
                    .trim(from: 0, to: isRefreshing ? 1 : anim)
                    .stroke(
                        gradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: isRefreshing ? [8, 6] : [], dashPhase: dashPhase)
                    )
                    .frame(height: height + 8)
                    .onChange(of: isRefreshing) { _, refreshing in
                        if refreshing {
                            withAnimation(.easeInOut(duration: 0.25)) { anim = 1 }
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) { anim = 0 }
                        }
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


// 滚动偏移（用于M动画进度）
// Note: Using ScrollOffsetPreferenceKey from EnhancedDiscoverView.swift

// 其余 GentlePostCard / TagView / RecommendationCardView / PostImagesView 与之前一致，已保留。

