//
//  UserProfileView.swift
//  Melodii
//
//  完整的用户主页 - 显示资料和帖子
//

import SwiftUI
import PhotosUI

struct UserProfileView: View {
    let user: User

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var displayUser: User
    @State private var userPosts: [Post] = []
    @State private var isLoadingPosts = false
    @State private var isFollowing = false
    @State private var isTogglingFollow = false
    @State private var showMessage = false
    @State private var showEditProfile = false

    init(user: User) {
        self.user = user
        _displayUser = State(initialValue: user)
    }

    // 为私信准备的本地会话与对方用户
    @State private var pendingConversation: Conversation?
    @State private var pendingOtherUser: User?

    // 头像/封面
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isUploadingCover = false
    @State private var coverPreviewURL: String?

    var isOwnProfile: Bool {
        user.id == authService.currentUser?.id
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 封面图和头像区域
                profileHeaderView

                // 用户信息区域
                profileInfoView
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayUser.id)

                // 操作按钮
                if !isOwnProfile {
                    actionButtonsView
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isFollowing)
                }

                Divider()
                    .padding(.vertical, 20)

                // 帖子列表
                postsSection
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 编辑资料
                        Button {
                            showEditProfile = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        // 更换头像
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                            if isUploadingAvatar {
                                ProgressView()
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                        }
                        // 更换封面
                        PhotosPicker(selection: $selectedCoverItem, matching: .images, photoLibrary: .shared()) {
                            if isUploadingCover {
                                ProgressView()
                            } else {
                                Image(systemName: "photo.badge.plus")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(user: user)
        }
        // 进入聊天：使用 ConversationView(conversation:otherUser:)
        .sheet(isPresented: $showMessage) {
            if let conv = pendingConversation, let other = pendingOtherUser {
                NavigationStack { ConversationView(conversation: conv, otherUser: other) }
            }
        }
        .task {
            await loadData()
        }
        .onChange(of: selectedAvatarItem) { _, newValue in
            if let item = newValue {
                Task { await handlePickAvatar(item: item) }
            }
        }
        .onChange(of: selectedCoverItem) { _, newValue in
            if let item = newValue {
                Task { await handlePickCover(item: item) }
            }
        }
    }

    // MARK: - Profile Header (Cover + Avatar)

    private var profileHeaderView: some View {
        ZStack(alignment: .bottom) {
            // 封面图（优先预览，其次用户coverImageURL，否则渐变占位）
            Group {
                if let preview = coverPreviewURL, let url = URL(string: preview) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: Color(.systemGray5)
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: Color(.systemGray5)
                        @unknown default: Color(.systemGray5)
                        }
                    }
                } else if let cover = displayUser.coverImageURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: Color(.systemGray5)
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: Color(.systemGray5)
                        @unknown default: Color(.systemGray5)
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 180)
            .clipped()

            // 头像
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.8), .pink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                if let avatar = displayUser.avatarURL, let url = URL(string: avatar) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: Color.clear
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: Color.clear
                        @unknown default: Color.clear
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    Text(displayUser.initials)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 4)
            )
            .offset(y: 50)
        }
        .frame(height: 230)
    }

    // MARK: - Profile Info

    private var profileInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 昵称
            Text(displayUser.nickname)
                .font(.title2)
                .fontWeight(.bold)

            // MID
            HStack(spacing: 8) {
                Text("MID:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(displayUser.mid ?? "-")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)

                Button {
                    UIPasteboard.general.string = displayUser.mid ?? "-"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            // 统计信息卡片
            HStack(spacing: 12) {
                StatCardView(
                    title: "帖子",
                    count: userPosts.count,
                    icon: "square.text.square",
                    gradient: [.blue, .cyan],
                    delay: 0.0
                )

                StatCardView(
                    title: "粉丝",
                    count: displayUser.followersCount ?? 0,
                    icon: "person.2",
                    gradient: [.purple, .pink],
                    delay: 0.1
                )

                StatCardView(
                    title: "关注",
                    count: displayUser.followingCount ?? 0,
                    icon: "person.badge.plus",
                    gradient: [.green, .mint],
                    delay: 0.2
                )

                StatCardView(
                    title: "获赞",
                    count: displayUser.likesCount ?? 0,
                    icon: "heart.fill",
                    gradient: [.pink, .orange],
                    delay: 0.3
                )
            }
            .padding(.vertical, 8)

            // 个人简介
            if let bio = displayUser.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            // 兴趣标签
            if !displayUser.interests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(displayUser.interests, id: \.self) { interest in
                            Text(interest)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Buttons

    @State private var messageButtonPressed = false
    @State private var followButtonPressed = false

    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            // 私信按钮
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await openConversation() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "message.fill")
                    Text("私信")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(messageButtonPressed ? 0 : 0.05), radius: messageButtonPressed ? 2 : 6, x: 0, y: messageButtonPressed ? 1 : 3)
            }
            .scaleEffect(messageButtonPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: messageButtonPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in messageButtonPressed = true }
                    .onEnded { _ in messageButtonPressed = false }
            )

            // 关注按钮
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await toggleFollow() }
            } label: {
                Group {
                    if isTogglingFollow {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(isFollowing ? "已关注" : "关注")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isFollowing ?
                    LinearGradient(colors: [.gray.opacity(0.8), .gray], startPoint: .leading, endPoint: .trailing) :
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(
                    color: isFollowing ? Color.clear : Color.blue.opacity(followButtonPressed ? 0.1 : 0.3),
                    radius: followButtonPressed ? 4 : 10,
                    x: 0,
                    y: followButtonPressed ? 2 : 5
                )
            }
            .scaleEffect(followButtonPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: followButtonPressed)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isFollowing)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isTogglingFollow { followButtonPressed = true } }
                    .onEnded { _ in followButtonPressed = false }
            )
            .disabled(isTogglingFollow)
        }
    }

    // MARK: - Posts Section

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isOwnProfile ? "我的帖子" : "Ta 的帖子")
                .font(.headline)
                .padding(.horizontal, 20)

            if isLoadingPosts {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if userPosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(isOwnProfile ? "还没有发布帖子" : "Ta 还没有发布帖子")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(userPosts) { post in
                        Group {
                            if isOwnProfile {
                                PostRowForProfile(post: post)
                                    .padding(Edge.Set.horizontal, 16)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task { await deletePost(post) }
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        Button {
                                            Task { await hidePost(post) }
                                        } label: {
                                            Label("隐藏", systemImage: "eye.slash")
                                        }
                                    }
                            } else {
                                PostRowForProfile(post: post)
                                    .padding(Edge.Set.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        await loadFollowStatus()
        await loadUserPosts()
    }

    private func loadFollowStatus() async {
        guard let userId = authService.currentUser?.id, !isOwnProfile else { return }

        do {
            isFollowing = try await supabaseService.isFollowing(followerId: userId, followingId: user.id)
        } catch {
            print("加载关注状态失败: \(error)")
        }
    }

    private func loadUserPosts() async {
        isLoadingPosts = true

        do {
            userPosts = try await supabaseService.fetchUserPosts(userId: user.id)
        } catch {
            print("加载用户帖子失败: \(error)")
        }

        isLoadingPosts = false
    }

    private func toggleFollow() async {
        guard let userId = authService.currentUser?.id else { return }

        isTogglingFollow = true
        let wasFollowing = isFollowing

        do {
            if wasFollowing {
                // 取消关注
                try await supabaseService.unfollowUser(followerId: userId, followingId: user.id)
                await MainActor.run {
                    isFollowing = false
                }
            } else {
                // 关注
                try await supabaseService.followUser(followerId: userId, followingId: user.id)
                await MainActor.run {
                    isFollowing = true
                }
            }

            // 重新加载用户数据以更新统计信息
            await reloadUserData()

            // 确保关注状态与数据库同步
            await loadFollowStatus()
        } catch {
            // 如果失败，恢复原状态
            await MainActor.run {
                isFollowing = wasFollowing
            }
            print("关注操作失败: \(error)")
        }

        isTogglingFollow = false
    }

    private func reloadUserData() async {
        do {
            let updatedUser = try await supabaseService.fetchUser(id: user.id)
            await MainActor.run {
                displayUser = updatedUser
            }
        } catch {
            print("重新加载用户数据失败: \(error)")
        }
    }

    // MARK: - Open Conversation

    private func openConversation() async {
        guard let myId = authService.currentUser?.id else { return }
        do {
            // 获取或创建会话
            let convId = try await supabaseService.getOrCreateConversation(user1Id: myId, user2Id: user.id)
            let conv = try await supabaseService.fetchConversation(id: convId, currentUserId: myId)
            pendingConversation = conv
            pendingOtherUser = user
            showMessage = true
        } catch {
            print("打开会话失败: \(error)")
        }
    }

    // MARK: - Avatar / Cover Upload

    private func handlePickAvatar(item: PhotosPickerItem) async {
        guard let myId = authService.currentUser?.id else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // 简单判断 mime
                let mime = "image/jpeg"
                let url = try await supabaseService.uploadUserMedia(
                    data: data,
                    mime: mime,
                    fileName: nil,
                    folder: "avatars/\(myId)"
                )
                try await supabaseService.updateUser(id: myId, nickname: nil, bio: nil, avatarURL: url, coverURL: nil)

                // 本地刷新用户资料（如果你有 AuthService.currentUser 可变）
                authService.currentUser?.avatarURL = url
            }
        } catch {
            print("上传头像失败: \(error)")
        }
    }

    private func handlePickCover(item: PhotosPickerItem) async {
        guard let myId = authService.currentUser?.id else { return }
        isUploadingCover = true
        defer { isUploadingCover = false }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let mime = "image/jpeg"
                let url = try await supabaseService.uploadUserMedia(
                    data: data,
                    mime: mime,
                    fileName: nil,
                    folder: "covers/\(myId)"
                )
                // 更新数据库 + 本地预览
                try await supabaseService.updateUser(id: myId, nickname: nil, bio: nil, avatarURL: nil, coverURL: url)
                coverPreviewURL = url
                authService.currentUser?.coverImageURL = url
            }
        } catch {
            print("上传封面失败: \(error)")
        }
    }

    // MARK: - Post Actions (own profile)

    private func deletePost(_ post: Post) async {
        do {
            try await supabaseService.deletePost(id: post.id)
            userPosts.removeAll { $0.id == post.id }
        } catch {
            print("删除失败: \(error)")
        }
    }

    private func hidePost(_ post: Post) async {
        do {
            try await supabaseService.hidePost(id: post.id)
            userPosts.removeAll { $0.id == post.id }
        } catch {
            print("隐藏失败: \(error)")
        }
    }
}

// MARK: - Minimal Post Row for Profile (local to this file)

private struct PostRowForProfile: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 文本
            if let text = post.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }

            // 简单媒体预览（最多3张）
            if !post.mediaURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.mediaURLs.prefix(3), id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { phase in
                                switch phase {
                                case .empty:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                        .frame(width: 100, height: 100)
                                        .overlay(ProgressView())
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .failure:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray6))
                                        .frame(width: 100, height: 100)
                                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
            }

            // 简要统计
            HStack(spacing: 16) {
                Label("\(post.likeCount)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(post.collectCount)", systemImage: "bookmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

// MARK: - Stat Card Component

private struct StatCardView: View {
    let title: String
    let count: Int
    let icon: String
    let gradient: [Color]
    let delay: Double

    @State private var appeared = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(
                        color: gradient.first?.opacity(appeared ? 0.3 : 0) ?? .clear,
                        radius: appeared ? 8 : 0,
                        x: 0,
                        y: appeared ? 4 : 0
                    )

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: appeared)
            }

            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.headline)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(delay), value: appeared)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear {
            appeared = true
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

#Preview {
    NavigationStack {
        UserProfileView(user: User(id: "123", mid: "M123456", nickname: "测试用户"))
    }
}
