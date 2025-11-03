//
//  PostDetailView.swift
//  Melodii
//
//  公共的帖子详情视图（从 Discover/Home 均可跳转）
//

import SwiftUI

struct PostDetailView: View {
    let post: Post

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
    @State private var selectedImageIndex: Int? = nil
    @FocusState private var isCommentFieldFocused: Bool
    @State private var showShare = false

    init(post: Post) {
        self.post = post
        _likeCount = State(initialValue: post.likeCount)
        _commentCount = State(initialValue: post.commentCount)
        _collectCount = State(initialValue: post.collectCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 作者信息
                HStack(spacing: 12) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(post.author.initials)
                                .font(.title3)
                                .foregroundStyle(Color.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        let displayName = (post.author.nickname == "Loading...") ? "用户" : post.author.nickname
                        Text(displayName)
                            .font(.headline)

                        Text(post.createdAt.timeAgoDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 关注按钮
                    if let userId = authService.currentUser?.id, userId != post.author.id {
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

                // 图片展示
                if !post.mediaURLs.isEmpty {
                    TabView(selection: $selectedImageIndex) {
                        ForEach(Array(post.mediaURLs.enumerated()), id: \.offset) { index, url in
                            AsyncImage(url: URL(string: url)) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle()
                                        .fill(Color(.systemGray6))
                                        .overlay(ProgressView())
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                case .failure:
                                    Rectangle()
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.largeTitle)
                                                .foregroundStyle(.secondary)
                                        )
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 400)
                            .tag(index)
                        }
                    }
                    .frame(height: 400)
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }

                // 交互按钮
                HStack(spacing: 24) {
                    // 点赞
                    Button {
                        Task { await toggleLike() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .foregroundStyle(isLiked ? .red : .primary)
                            Text("\(likeCount)")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingLike)

                    // 评论
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("\(commentCount)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)

                    // 收藏
                    Button {
                        Task { await toggleCollect() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(isCollected ? .blue : .primary)
                            Text("\(collectCount)")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingCollect)

                    Spacer()

                    // 分享
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
                    Text("评论 \(commentCount)")
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
                        ForEach(comments) { comment in
                            CommentRow(comment: comment) { replyTo in
                                replyToComment = replyTo
                                commentText = ""
                                isCommentFieldFocused = true
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .navigationTitle("动态详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if authService.isAuthenticated {
                VStack(spacing: 0) {
                    if let replyTo = replyToComment {
                        let replyName = (replyTo.author.nickname == "Loading...") ? "用户" : replyTo.author.nickname
                        HStack {
                            Text("回复 @\(replyName)")
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
        .task {
            await loadData()
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Data Loading

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
            } else {
                try await supabaseService.unlikePost(userId: userId, postId: post.id)
            }
        } catch {
            isLiked = wasLiked
            likeCount += wasLiked ? 1 : -1
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
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
            } else {
                try await supabaseService.uncollectPost(userId: userId, postId: post.id)
            }
        } catch {
            isCollected = wasCollected
            collectCount += wasCollected ? 1 : -1
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
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
            } else {
                try await supabaseService.unfollowUser(followerId: userId, followingId: post.author.id)
            }
        } catch {
            isFollowing = wasFollowing
            alertMessage = "操作失败: \(error.localizedDescription)"
            showAlert = true
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
        } catch {
            alertMessage = "发送失败: \(error.localizedDescription)"
            showAlert = true
        }

        isSubmittingComment = false
    }
}

// MARK: - Comment Row (简化版，复用你在 DiscoverView 的样式)

private struct CommentRow: View {
    let comment: Comment
    let onReply: (Comment) -> Void

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var isLiked = false
    @State private var likeCount: Int
    @State private var replies: [Comment] = []
    @State private var showReplies = false
    @State private var isLoadingReplies = false
    @State private var isTogglingLike = false

    init(comment: Comment, onReply: @escaping (Comment) -> Void) {
        self.comment = comment
        self.onReply = onReply
        _likeCount = State(initialValue: comment.likeCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.6), .pink.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(comment.author.initials)
                            .font(.caption)
                            .foregroundStyle(Color.white)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        let displayName = (comment.author.nickname == "Loading...") ? "用户" : comment.author.nickname
                        Text(displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(comment.createdAt.timeAgoDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(comment.text)
                        .font(.body)

                    HStack(spacing: 20) {
                        Button {
                            Task { await toggleLike() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.caption)
                                    .foregroundStyle(isLiked ? .red : .secondary)

                                if likeCount > 0 {
                                    Text("\(likeCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTogglingLike)

                        Button {
                            onReply(comment)
                        } label: {
                            Text("回复")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if comment.replyToId == nil {
                            Button {
                                Task {
                                    if showReplies {
                                        showReplies = false
                                    } else {
                                        await loadReplies()
                                        showReplies = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showReplies ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                    if !replies.isEmpty {
                                        Text("\(replies.count)条回复")
                                            .font(.caption)
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }

            if showReplies && !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(replies) { reply in
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .frame(width: 2)
                                .padding(.leading, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    let name = (reply.author.nickname == "Loading...") ? "用户" : reply.author.nickname
                                    Text(name)
                                        .font(.caption)
                                        .fontWeight(.semibold)

                                    Text(reply.createdAt.timeAgoDisplay)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(reply.text)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.leading, 48)
            }

            if isLoadingReplies {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 8)
        .task {
            await loadLikeStatus()
        }
    }

    private func loadLikeStatus() async {
        guard let userId = authService.currentUser?.id else { return }
        do {
            isLiked = try await supabaseService.hasLikedComment(userId: userId, commentId: comment.id)
        } catch {
            print("加载评论点赞状态失败: \(error)")
        }
    }

    private func toggleLike() async {
        guard let userId = authService.currentUser?.id else { return }

        isTogglingLike = true
        let wasLiked = isLiked
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        do {
            if isLiked {
                try await supabaseService.likeComment(userId: userId, commentId: comment.id)
            } else {
                try await supabaseService.unlikeComment(userId: userId, commentId: comment.id)
            }
        } catch {
            isLiked = wasLiked
            likeCount += wasLiked ? 1 : -1
            print("评论点赞操作失败: \(error)")
        }
        isTogglingLike = false
    }

    private func loadReplies() async {
        isLoadingReplies = true
        do {
            replies = try await supabaseService.fetchCommentReplies(commentId: comment.id)
        } catch {
            print("加载回复失败: \(error)")
        }
        isLoadingReplies = false
    }
}
