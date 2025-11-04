//
//  ProfileView.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import SwiftUI

struct ProfileView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    @State private var userPosts: [Post] = []
    @State private var isLoading = false
    @State private var showSignIn = false
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("我的")
                .task {
                    if authService.isAuthenticated, let userId = authService.currentUser?.id {
                        await loadUserPosts(userId: userId)
                    }
                }
                .sheet(isPresented: $showSignIn) {
                    SignInView()
                }
                .sheet(isPresented: $showEditProfile) {
                    if let current = authService.currentUser {
                        EditProfileView(user: current)
                    }
                }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if authService.isAuthenticated, let user = authService.currentUser {
                authenticatedView(user: user)
            } else {
                unauthenticatedView
            }
        }
    }

    @ViewBuilder
    private func authenticatedView(user: User) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                userInfoCard(user: user)
                functionsListSection(user: user)
                settingsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func userInfoCard(user: User) -> some View {
        VStack(spacing: 0) {
            coverImageView(user: user)

            VStack(spacing: 12) {
                avatarView(user: user)
                    .padding(.top, -40)

                Text(user.nickname)
                    .font(.title2)
                    .bold()
                    .padding(.top, -30)

                if let mid = user.mid {
                    midView(mid: mid)
                        .padding(.top, -10)
                }

                if let bio = user.bio {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, -5)
                }

                editProfileButton
                    .padding(.top, 5)

                statsView(user: user)
                    .padding(.top, 12)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private func coverImageView(user: User) -> some View {
        if let coverURL = user.coverImageURL, !coverURL.isEmpty {
            AsyncImage(url: URL(string: coverURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipped()
            } placeholder: {
                coverPlaceholder
            }
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.4), .pink.opacity(0.4), .orange.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 140)
            .overlay(
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: -50, y: -30)
            )
    }

    @ViewBuilder
    private func avatarView(user: User) -> some View {
        Group {
            if let avatarURL = user.avatarURL, !avatarURL.isEmpty {
                AsyncImage(url: URL(string: avatarURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 4)
                        )
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                        .overlay(
                            ProgressView()
                        )
                }
            } else {
                avatarPlaceholder(user: user)
            }
        }
    }

    private func avatarPlaceholder(user: User) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.8), .pink.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 80, height: 80)
            .overlay(
                Text(user.initials)
                    .font(.title)
                    .foregroundStyle(.white)
            )
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 4)
            )
    }

    private func midView(mid: String) -> some View {
        HStack(spacing: 6) {
            Text("MID: \(mid)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                UIPasteboard.general.string = mid
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var editProfileButton: some View {
        Button {
            showEditProfile = true
        } label: {
            Text("编辑资料")
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
    }

    private func statsView(user: User) -> some View {
        HStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("\(user.followingCount ?? 0)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("关注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("\(user.followersCount ?? 0)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("粉丝")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("\(user.likesCount ?? 0)")
                    .font(.headline)
                Text("获赞")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("\(userPosts.count)")
                    .font(.headline)
                Text("帖子")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func functionsListSection(user: User) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                UserPostsListView(userId: user.id)
            } label: {
                ProfileRowView(icon: "doc.text", title: "我的帖子", value: "\(userPosts.count)")
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                CollectionsView()
            } label: {
                ProfileRowView(icon: "bookmark", title: "我的收藏")
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                DraftsView(userId: user.id)
            } label: {
                ProfileRowView(icon: "square.and.pencil", title: "草稿箱")
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SettingsView()
            } label: {
                ProfileRowView(icon: "gear", title: "设置")
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var unauthenticatedView: some View {
        ContentUnavailableView {
            Label("未登录", systemImage: "person.crop.circle")
        } description: {
            Text("登录后可查看个人信息、发布内容和收藏")
        } actions: {
            Button {
                showSignIn = true
            } label: {
                Text("使用Apple登录")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }

    private func loadUserPosts(userId: String) async {
        isLoading = true
        do {
            userPosts = try await supabaseService.fetchUserPosts(userId: userId)
        } catch {
            print("加载用户帖子失败: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Profile Row View

private struct ProfileRowView: View {
    let icon: String
    let title: String
    var value: String?
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isDestructive ? .red : .primary)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(isDestructive ? .red : .primary)

            Spacer()

            if let value = value {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - User Posts List View

private struct UserPostsListView: View {
    let userId: String

    @StateObject private var supabaseService = SupabaseService.shared
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if posts.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("还没有帖子", systemImage: "doc.text")
                } description: {
                    Text("发布第一条帖子\n分享你的想法和生活")
                }
            } else {
                List {
                    ForEach(posts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            UserPostRow(post: post)
                        }
                        .swipeActions(edge: .trailing) {
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
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的帖子")
        .refreshable {
            await loadPosts()
        }
        .task {
            await loadPosts()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadPosts() async {
        isLoading = true
        do {
            posts = try await supabaseService.fetchUserPosts(userId: userId)
            print("✅ 加载了 \(posts.count) 个帖子")
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
            showError = true
            print("❌ 加载失败: \(error)")
        }
        isLoading = false
    }

    private func deletePost(_ post: Post) async {
        do {
            try await supabaseService.deletePost(id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
            showError = true
            print("❌ 删除失败: \(error)")
        }
    }

    private func hidePost(_ post: Post) async {
        do {
            try await supabaseService.hidePost(id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = "隐藏失败: \(error.localizedDescription)"
            showError = true
            print("❌ 隐藏失败: \(error)")
        }
    }
}

// MARK: - User Post Row

private struct UserPostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 帖子内容
            if let text = post.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineLimit(3)
            }

            // 媒体预览
            if !post.mediaURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.mediaURLs.prefix(3), id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray6))
                                    .frame(width: 60, height: 60)
                            }
                        }
                    }
                }
            }

            // 统计和状态
            HStack {
                Label("\(post.likeCount)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if post.status == .draft {
                    Text("草稿")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }

                Text(post.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Collections View

private struct CollectionsView: View {
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var authService = AuthService.shared

    @State private var collectedPosts: [Post] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if collectedPosts.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("还没有收藏", systemImage: "bookmark")
                } description: {
                    Text("浏览帖子时点击收藏按钮\n可以将喜欢的内容保存到这里")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(collectedPosts) { post in
                            NavigationLink {
                                PostDetailView(post: post)
                            } label: {
                                CollectionPostCard(post: post, onUncollect: {
                                    Task { await uncollectPost(post) }
                                })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("我的收藏")
        .refreshable {
            await loadCollections()
        }
        .task {
            await loadCollections()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadCollections() async {
        guard let userId = authService.currentUser?.id else { return }
        isLoading = true

        do {
            collectedPosts = try await supabaseService.fetchUserCollections(userId: userId)
            print("✅ 加载了 \(collectedPosts.count) 个收藏")
        } catch {
            errorMessage = "加载收藏失败: \(error.localizedDescription)"
            showError = true
            print("❌ 加载收藏失败: \(error)")
        }

        isLoading = false
    }

    private func uncollectPost(_ post: Post) async {
        guard let userId = authService.currentUser?.id else { return }

        do {
            try await supabaseService.uncollectPost(userId: userId, postId: post.id)
            collectedPosts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = "取消收藏失败: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Collection Post Card

private struct CollectionPostCard: View {
    let post: Post
    let onUncollect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 作者信息
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(post.author.initials)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.nickname)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(post.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onUncollect()
                } label: {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(.yellow)
                }
            }

            // 帖子内容
            if let text = post.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .lineLimit(4)
                    .foregroundStyle(.primary)
            }

            // 媒体预览
            if !post.mediaURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.mediaURLs.prefix(3), id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                                    .frame(width: 100, height: 100)
                                    .overlay(ProgressView())
                            }
                        }
                    }
                }
            }

            // 统计信息
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
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Drafts View (占位)

private struct DraftsView: View {
    let userId: String

    @StateObject private var supabaseService = SupabaseService.shared
    @State private var drafts: [Post] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isEditing = false
    @State private var editingPost: Post?

    var body: some View {
        Group {
            if drafts.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("还没有草稿", systemImage: "square.and.pencil")
                } description: {
                    Text("创建帖子时可以先保存为草稿\n稍后再继续编辑")
                }
            } else {
                List {
                    ForEach(drafts) { post in
                        VStack(alignment: .leading, spacing: 6) {
                            if let text = post.text, !text.isEmpty {
                                Text(text)
                                    .lineLimit(2)
                            } else {
                                Text("（无文本内容）")
                                    .foregroundStyle(.secondary)
                            }
                            Text(post.createdAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                editingPost = post
                                isEditing = true
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button {
                                Task { await republish(post) }
                            } label: {
                                Label("重新发布", systemImage: "arrow.uturn.up")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                Task { await deleteDraft(post) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("草稿箱")
        .task { await loadDrafts() }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .refreshable { await loadDrafts() }
        .sheet(isPresented: $isEditing) {
            if let draft = editingPost {
                CreateView(draftPost: draft)
            }
        }
    }

    private func loadDrafts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            drafts = try await supabaseService.fetchDraftPosts(userId: userId)
        } catch {
            errorMessage = "加载草稿失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func republish(_ post: Post) async {
        do {
            try await supabaseService.publishPost(id: post.id)
            drafts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = "重新发布失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteDraft(_ post: Post) async {
        do {
            try await supabaseService.deletePost(id: post.id)
            drafts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Sign In View

private struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    @State private var isSigningIn = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                // Logo
                Image(systemName: "music.note.list")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("欢迎来到 Melodii")
                    .font(.title)
                    .bold()

                Text("和你一起记录生活的美好")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Apple登录按钮
                Button {
                    Task {
                        await signInWithApple()
                    }
                } label: {
                    HStack {
                        Image(systemName: "applelogo")
                        Text("使用Apple登录")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSigningIn)

                if isSigningIn {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("登录失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func signInWithApple() async {
        isSigningIn = true

        do {
            let coordinator = AppleSignInCoordinator()
            let (idToken, nonce) = try await coordinator.signIn()
            try await authService.signInWithApple(idToken: idToken, nonce: nonce)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSigningIn = false
    }
}

#Preview {
    ProfileView()
}
