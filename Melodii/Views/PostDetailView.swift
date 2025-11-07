//
//  PostDetailView.swift
//  Melodii
//
//  公共的帖子详情视图（从 Discover/Home/通知 均可跳转）
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

struct PostDetailView: View {
    let post: Post
    let scrollToCommentId: String?

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var comments: [Comment] = []
    @State private var commentText = ""
    @State private var replyToComment: Comment? = nil
    @State private var isLiked = false
    @State private var isCollected = false
    @State private var isFollowing = false
    @State private var likeCount: Int
    @State private var commentCount: Int
    @State private var collectCount: Int

    @State private var isLoadingComments = false
    @State private var isSubmittingComment = false
    @State private var isTogglingFollow = false
    @State private var isTogglingLike = false
    @State private var isTogglingCollect = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @FocusState private var isCommentFieldFocused: Bool
    @State private var showShare = false

    // 全屏媒体预览
    @State private var showViewer = false
    @State private var viewerIndex = 0

    // 评论滚动
    @State private var pendingScrollTarget: String?
    // 评论交互
    @State private var expandedThreads: Set<String> = []
    @State private var commentToDelete: Comment? = nil
    @State private var showDeleteConfirm: Bool = false

    init(post: Post, commentId: String? = nil) {
        self.post = post
        self.scrollToCommentId = commentId
        _likeCount = State(initialValue: post.likeCount)
        _commentCount = State(initialValue: post.commentCount)
        _collectCount = State(initialValue: post.collectCount)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 作者信息
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
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(post.isAnonymous ? "匿" : post.author.initials)
                                        .font(.title3)
                                        .foregroundStyle(Color.white)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(post.isAnonymous)

                        NavigationLink(destination: UserProfileView(user: post.author)) {
                            VStack(alignment: .leading, spacing: 4) {
                                // 匿名帖子显示"匿名"，非匿名帖子显示真实昵称
                                let displayName = post.isAnonymous ? "匿名" : post.author.nickname
                                Text(displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                // 显示 MID 和时间
                                HStack(spacing: 6) {
                                    // 匿名帖子不显示MID
                                    if !post.isAnonymous {
                                        if let mid = post.author.mid, !mid.isEmpty {
                                            Text("@\(mid)")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        } else {
                                            Text("@\(post.author.id.prefix(8))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("@匿名用户")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)

                                    Text(post.createdAt.timeAgoDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        
                                    if let city = post.city, !city.isEmpty {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                        
                                        Text(city)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // 关注按钮（匿名作者不允许关注）
                        if !post.isAnonymous, let userId = authService.currentUser?.id, userId != post.author.id {
                            Button {
                                Task { await toggleFollow() }
                            } label: {
                                Group {
                                    if isTogglingFollow {
                                        ProgressView()
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Text(isFollowing ? "已关注" : "关注")
                                    }
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(isFollowing ? .primary : Color.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    Group {
                                        if isFollowing {
                                            Color(.systemGray5)
                                        } else {
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        }
                                    }
                                )
                                .clipShape(Capsule())
                            }
                            .disabled(isTogglingFollow)
                        }
                    }
                    .padding(16)

                    // 媒体展示（点击放大）
                    if !post.mediaURLs.isEmpty {
                        TabView(selection: $viewerIndex) {
                            ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { index, url in
                                MediaPage(urlString: url)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewerIndex = index
                                        showViewer = true
                                    }
                                    .tag(index)
                            }
                        }
                        .frame(height: 400)
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .sheet(isPresented: $showViewer) {
                            FullscreenMediaViewer(urls: post.mediaURLs, isPresented: $showViewer, index: viewerIndex)
                        }
                    }

                    // 交互按钮（显示数量）
                    HStack(spacing: 24) {
                        Button {
                            Task { await toggleLike() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .foregroundStyle(isLiked ? .red : .primary)
                                Text(String(likeCount))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(isLiked ? .red : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTogglingLike)

                        Button {
                            isCommentFieldFocused = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "text.bubble")
                                    .foregroundStyle(.secondary)
                                Text(String(commentCount))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await toggleCollect() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(isCollected ? .blue : .primary)
                                if collectCount > 0 {
                                    Text(String(collectCount))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(isCollected ? .blue : .secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTogglingCollect)

                        Spacer()

                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.primary)
                        }
                        .sheet(isPresented: $showShare) {
                            let text = post.text ?? ""
                            let urls = post.mediaURLs.compactMap { URL(string: $0) }
                            ShareSheet(activityItems: [text] + urls)
                        }
                    }
                    .font(.title3)
                    .padding(16)

                    // 文字内容
                    if let text = post.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // 话题标签
                    if !post.topics.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(post.topics, id: \.self) { topic in
                                    Text("#\(topic)")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 16)
                    }

                    Divider()
                        .padding(.horizontal, 16)

                    // 评论区
                    VStack(alignment: .leading, spacing: 12) {
                        Text("评论")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        if isLoadingComments {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding()
                        } else if comments.isEmpty {
                            Text("还没有评论，来说点什么吧～")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            // 分组显示为线程：顶层评论 + 子回复
                            ForEach(buildCommentThreads(from: comments)) { thread in
                                VStack(alignment: .leading, spacing: 8) {
                                    // 顶层评论
                                    CommentItemView(
                                        comment: thread.root,
                                        parentAuthorName: nil,
                                        canDelete: authService.currentUser?.id == thread.root.authorId,
                                        onCopy: { copyComment($0) },
                                        onDelete: { target in
                                            commentToDelete = target
                                            showDeleteConfirm = true
                                        },
                                        onReport: { reportComment($0) }
                                    ) { replyTo in
                                        replyToComment = replyTo
                                        commentText = ""
                                        isCommentFieldFocused = true
                                    }
                                    .padding(.horizontal, 16)
                                    .id(thread.root.id)

                                    // 子回复（缩进 + 竖线引导）
                                    if !thread.replies.isEmpty {
                                        let isExpanded = expandedThreads.contains(thread.id)
                                        let previewCount = 2
                                        let displayed = isExpanded ? thread.replies : Array(thread.replies.prefix(previewCount))
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(displayed) { reply in
                                                HStack(alignment: .top, spacing: 8) {
                                                    // 竖线引导层次
                                                    Rectangle()
                                                        .fill(Color(.systemGray5))
                                                        .frame(width: 2)
                                                        .cornerRadius(1)

                                                    CommentItemView(
                                                        comment: reply,
                                                        parentAuthorName: thread.root.author.nickname,
                                                        canDelete: authService.currentUser?.id == reply.authorId,
                                                        onCopy: { copyComment($0) },
                                                        onDelete: { target in
                                                            commentToDelete = target
                                                            showDeleteConfirm = true
                                                        },
                                                        onReport: { reportComment($0) }
                                                    ) { selected in
                                                        replyToComment = selected
                                                        commentText = ""
                                                        isCommentFieldFocused = true
                                                    }
                                                    .id(reply.id)
                                                }
                                                .padding(.leading, 16)
                                                .padding(.trailing, 8)
                                            }
                                            // 展开/收起控制
                                            if thread.replies.count > displayed.count {
                                                Button {
                                                    expandedThreads.insert(thread.id)
                                                } label: {
                                                    Text("展开 \(thread.replies.count - displayed.count) 条回复")
                                                        .font(.caption)
                                                        .foregroundStyle(.blue)
                                                }
                                                .padding(.leading, 24)
                                            } else if isExpanded && thread.replies.count > previewCount {
                                                Button {
                                                    expandedThreads.remove(thread.id)
                                                } label: {
                                                    Text("收起回复")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.leading, 24)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(.bottom, 80)
                }
            }
            .onChange(of: comments.count) { _, _ in
                if let target = pendingScrollTarget {
                    pendingScrollTarget = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
        .navigationTitle("动态详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if authService.isAuthenticated {
                VStack(spacing: 0) {
                    if let replyTo = replyToComment {
                        HStack {
                            Text("回复 @\(replyTo.author.nickname)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                replyToComment = nil
                                commentText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                    }

                    HStack(spacing: 12) {
                        TextField(replyToComment == nil ? "写评论..." : "写回复...", text: $commentText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .focused($isCommentFieldFocused)

                        Button {
                            Task { await submitComment() }
                        } label: {
                            if isSubmittingComment {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .foregroundStyle(commentText.isEmpty ? .gray : .blue)
                            }
                        }
                        .disabled(commentText.isEmpty || isSubmittingComment)
                    }
                    .padding()
                }
                .background(.ultraThinMaterial)
            }
        }
        .task(id: "\(post.id)|\(scrollToCommentId ?? "")") {
            await loadData()
            if let target = scrollToCommentId, !target.isEmpty {
                pendingScrollTarget = target
            }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .navigationDestination(for: User.self) { user in
            UserProfileView(user: user)
        }
        .alert("删除评论", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let target = commentToDelete {
                    Task { await deleteComment(target) }
                }
            }
        } message: {
            Text("确定删除这条评论吗？此操作不可恢复")
        }
    }

    // MARK: - Data

    private func loadData() async {
        if let userId = authService.currentUser?.id {
            isLiked = (try? await supabaseService.hasLikedPost(userId: userId, postId: post.id)) ?? false
            isCollected = (try? await supabaseService.hasCollectedPost(userId: userId, postId: post.id)) ?? false
            isFollowing = (try? await supabaseService.isFollowing(followerId: userId, followingId: post.author.id)) ?? false
        }
        await loadComments()
    }

    private func loadComments() async {
        isLoadingComments = true
        do {
            comments = try await supabaseService.fetchComments(postId: post.id)
        } catch {
            print("加载评论失败: \(error)")
        }
        isLoadingComments = false
    }

    // MARK: - Interactions

    private func toggleLike() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        isTogglingLike = true
        let wasLiked = isLiked
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        do {
            if isLiked {
                try await supabaseService.likePost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                try await supabaseService.unlikePost(userId: userId, postId: post.id)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } catch {
            isLiked = wasLiked
            likeCount += wasLiked ? 1 : -1
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        isTogglingLike = false
    }

    private func toggleCollect() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        isTogglingCollect = true
        let wasCollected = isCollected
        isCollected.toggle()
        collectCount += isCollected ? 1 : -1

        do {
            if isCollected {
                try await supabaseService.collectPost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                try await supabaseService.uncollectPost(userId: userId, postId: post.id)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } catch {
            isCollected = wasCollected
            collectCount += wasCollected ? 1 : -1
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        isTogglingCollect = false
    }

    private func toggleFollow() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        isTogglingFollow = true

        let wasFollowing = isFollowing
        isFollowing.toggle()

        do {
            if isFollowing {
                try await supabaseService.followUser(followerId: userId, followingId: post.author.id)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } else {
                try await supabaseService.unfollowUser(followerId: userId, followingId: post.author.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        } catch {
            isFollowing = wasFollowing
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        isTogglingFollow = false
    }

    private func submitComment() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSubmittingComment = true

        do {
            let newComment = try await supabaseService.createComment(
                postId: post.id,
                authorId: userId,
                text: content,
                replyToId: replyToComment?.id
            )

            if replyToComment == nil {
                comments.insert(newComment, at: 0)
            } else {
                await loadComments()
            }

            commentCount += 1
            commentText = ""
            replyToComment = nil
            isCommentFieldFocused = false
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            alertMessage = "发送失败: \(error.localizedDescription)"
            showAlert = true
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        isSubmittingComment = false
    }

    private func copyComment(_ comment: Comment) {
        UIPasteboard.general.string = comment.text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteComment(_ comment: Comment) async {
        guard let uid = authService.currentUser?.id, uid == comment.authorId else {
            alertMessage = "只能删除自己的评论"
            showAlert = true
            return
        }
        do {
            try await supabaseService.deleteComment(id: comment.id, postId: post.id)
            await MainActor.run {
                comments.removeAll { $0.id == comment.id }
                commentCount = max(0, commentCount - 1)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            alertMessage = "删除失败：\(error.localizedDescription)"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func reportComment(_ comment: Comment) {
        guard let uid = authService.currentUser?.id else { return }
        Task {
            do {
                try await supabaseService.reportComment(
                    reporterId: uid,
                    reportedUserId: comment.authorId,
                    postId: post.id,
                    commentId: comment.id,
                    reason: nil as String?
                )
                await MainActor.run {
                    alertMessage = "已举报该评论，我们会尽快处理"
                    showAlert = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                await MainActor.run {
                    alertMessage = "举报失败：\(error.localizedDescription)"
                    showAlert = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// 单页媒体（用于 TabView 内）
private struct MediaPage: View {
    let urlString: String
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false

    private func isVideo(_ url: String) -> Bool {
        return url.isVideoURL // 使用扩展中的统一检测方法
    }

    var body: some View {
        Group {
            if isVideo(urlString) {
                ZStack {
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .onAppear {
                                player.play()
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else if hasError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.red)
                            Text("视频加载失败")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Button("重试") {
                                setupVideoPlayer()
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    } else if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("加载视频中...")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                    }
                }
                .onAppear {
                    setupVideoPlayer()
                }
                .onDisappear {
                    cleanupVideoPlayer()
                }
            } else {
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .empty:
                        Color(.systemGray6).overlay(
                            ProgressView()
                                .tint(.gray)
                        )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        Color(.systemGray6).overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("图片加载失败")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func setupVideoPlayer() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        isLoading = true
        hasError = false
        
        // 清理之前的播放器
        cleanupVideoPlayer()
        
        // 创建播放器
        let newPlayer = AVPlayer(url: url)
        
        // 监听播放器状态
        newPlayer.currentItem?.publisher(for: \.status)
            .sink { status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        isLoading = false
                        hasError = false
                        // 配置音频播放会话，确保视频声音正常
                        do {
                            let session = AVAudioSession.sharedInstance()
                            try session.setCategory(.playback, mode: .moviePlayback, options: [])
                            try session.setActive(true)
                        } catch {
                            print("⚠️ 配置音频会话失败: \(error)")
                        }
                        player = newPlayer
                        player?.isMuted = false
                        player?.volume = 1.0
                    case .failed:
                        isLoading = false
                        hasError = true
                        print("视频播放失败: \(newPlayer.currentItem?.error?.localizedDescription ?? "未知错误")")
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func cleanupVideoPlayer() {
        player?.pause()
        player = nil
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - 评论线程与视图

/// 单个线程：顶层评论 + 其直接子回复
private struct CommentThread: Identifiable {
    let id: String
    let root: Comment
    let replies: [Comment]
}

/// 评论条目视图：头像 + 名称 + 时间 +（可选）回复@谁 + 文本 + 操作
private struct CommentItemView: View {
    let comment: Comment
    let parentAuthorName: String?
    let canDelete: Bool
    let onCopy: (Comment) -> Void
    let onDelete: (Comment) -> Void
    let onReport: (Comment) -> Void
    let onReply: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                // 头像：优先使用真实头像，添加点击查看主页功能
                NavigationLink(destination: UserProfileView(user: comment.author)) {
                    if let urlString = comment.author.avatarURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Circle().fill(Color(.systemGray5))
                                    .frame(width: 28, height: 28)
                                    .overlay(ProgressView().scaleEffect(0.6))
                            case .success(let image):
                                image.resizable().scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            case .failure:
                                Circle()
                                    .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Text(comment.author.initials)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            @unknown default:
                                Circle().fill(Color(.systemGray5)).frame(width: 28, height: 28)
                            }
                        }
                    } else {
                        Circle()
                            .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(comment.author.initials)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(comment.author.nickname == "Loading..." ? "用户" : comment.author.nickname)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if let mid = comment.author.mid, !mid.isEmpty {
                            Text("@\(mid)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }

                        Text(comment.createdAt.timeAgoDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let parent = parentAuthorName, !parent.isEmpty {
                        Text("回复 @\(parent)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                // 快速回复按钮
                Button { onReply(comment) } label: {
                    Text("回复")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            Text(comment.text)
                .font(.body)
                .foregroundStyle(.primary)
                .contextMenu {
                    Button("复制") { onCopy(comment) }
                    if canDelete { Button("删除", role: .destructive) { onDelete(comment) } }
                    Button("举报") { onReport(comment) }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 将评论分组成线程：顶层评论 + 直接子回复（按时间正序）
private extension PostDetailView {
    func buildCommentThreads(from list: [Comment]) -> [CommentThread] {
        // 顶层评论：replyToId为空
        let roots = list.filter { $0.replyToId == nil }
            .sorted { $0.createdAt < $1.createdAt }

        // 子回复按父ID分组
        let repliesMap = Dictionary(grouping: list.filter { $0.replyToId != nil }, by: { $0.replyToId! })

        return roots.map { root in
            let replies = repliesMap[root.id]?.sorted { $0.createdAt < $1.createdAt } ?? []
            return CommentThread(id: root.id, root: root, replies: replies)
        }
    }
}
