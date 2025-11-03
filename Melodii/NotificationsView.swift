//
//  NotificationsView.swift
//  Melodii
//

import SwiftUI

struct NotificationsView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared

    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    // 路由状态
    @State private var pushPost: Post?
    @State private var pushCommentId: String?
    @State private var pushUser: User?

    var body: some View {
        NavigationStack {
            Group {
                if !authService.isAuthenticated {
                    ContentUnavailableView(
                        "未登录",
                        systemImage: "bell",
                        description: Text("登录后可查看通知")
                    )
                } else if isLoading && notifications.isEmpty {
                    ProgressView("加载中...")
                } else if notifications.isEmpty {
                    ContentUnavailableView(
                        "暂无通知",
                        systemImage: "bell.slash",
                        description: Text("当有人点赞或评论您的内容时，通知会显示在这里")
                    )
                } else {
                    List {
                        ForEach(notifications) { notification in
                            Button {
                                Task { await handleTap(notification) }
                            } label: {
                                NotificationRowView(notification: notification)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {} label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .onAppear {
                                if !notification.isRead {
                                    Task { await markAsRead(notification) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadNotifications() }
                }
            }
            .navigationTitle("通知")
            .toolbar {
                if !notifications.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await markAllAsRead() }
                            } label: {
                                Label("全部标记为已读", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { pushPost != nil },
                set: { newValue in if !newValue { pushPost = nil; pushCommentId = nil } }
            )) {
                if let post = pushPost {
                    PostDetailView(post: post, commentId: pushCommentId)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { pushUser != nil },
                set: { newValue in if !newValue { pushUser = nil } }
            )) {
                if let user = pushUser {
                    UserProfileView(user: user)
                }
            }
            .task {
                if authService.isAuthenticated {
                    await loadNotifications()
                    await subscribeRealtime()
                }
            }
            .onDisappear { Task { await RealtimeService.shared.unsubscribeNotifications() } }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Tap Handling

    private func handleTap(_ item: NotificationItem) async {
        switch item.type {
        case .like, .comment, .reply:
            // 需要跳到帖子详情；如果有评论则定位
            if let postId = item.post?.id {
                await openPost(postId: postId, commentId: nil)
            }
        case .follow:
            pushUser = item.actor
        }
    }

    private func openPost(postId: String, commentId: String?) async {
        do {
            let post = try await supabaseService.fetchPost(id: postId)
            pushPost = post
            pushCommentId = commentId
        } catch {
            alertMessage = "打开帖子失败：\(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Data Loading（保持与之前一致，含去重与排序）

    private func loadNotifications() async {
        guard let userId = authService.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let raw = try await supabaseService.fetchNotifications(userId: userId)
            var items: [NotificationItem] = []

            for notif in raw {
                let actor = (try? await supabaseService.fetchUser(id: notif.actorId)) ?? User(id: notif.actorId, nickname: "用户")
                var post: Post?
                if let postId = notif.postId {
                    post = try? await supabaseService.fetchPost(id: postId)
                }
                let item = NotificationItem(
                    id: notif.id, type: notif.type, actor: actor,
                    post: post, isRead: notif.isRead, createdAt: notif.createdAt
                )
                items.append(item)
            }

            notifications = uniqueById(items + notifications).sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            if (error as? CancellationError) != nil { return }
            alertMessage = "加载失败: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func markAsRead(_ notification: NotificationItem) async {
        do {
            try await supabaseService.markNotificationAsRead(id: notification.id)
            if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
                if notifications[idx].isRead == false {
                    notifications[idx].isRead = true
                    if unreadCenter.unreadNotifications > 0 {
                        unreadCenter.unreadNotifications -= 1
                    }
                }
            }
        } catch {
            print("标记已读失败: \(error)")
        }
    }

    private func markAllAsRead() async {
        await withTaskGroup(of: Void.self) { group in
            for n in notifications where !n.isRead {
                group.addTask { try? await supabaseService.markNotificationAsRead(id: n.id) }
            }
        }
        var changed = false
        for idx in notifications.indices {
            if notifications[idx].isRead == false {
                notifications[idx].isRead = true
                changed = true
            }
        }
        if changed { unreadCenter.unreadNotifications = 0 }
    }

    // MARK: - Realtime

    private func subscribeRealtime() async {
        guard let userId = authService.currentUser?.id else { return }
        await RealtimeService.shared.subscribeToNotifications(userId: userId) { notif in
            Task { @MainActor in
                let actor = (try? await supabaseService.fetchUser(id: notif.actorId)) ?? User(id: notif.actorId, nickname: "用户")
                var post: Post?
                if let postId = notif.postId {
                    post = try? await supabaseService.fetchPost(id: postId)
                }
                let item = NotificationItem(
                    id: notif.id, type: notif.type, actor: actor,
                    post: post, isRead: notif.isRead, createdAt: notif.createdAt
                )
                if !notifications.contains(where: { $0.id == item.id }) {
                    notifications.insert(item, at: 0)
                }
                notifications.sort(by: { $0.createdAt > $1.createdAt })
            }
        }
    }

    // MARK: - Helpers

    private func uniqueById(_ items: [NotificationItem]) -> [NotificationItem] {
        var seen = Set<String>()
        var result: [NotificationItem] = []
        for i in items where !seen.contains(i.id) {
            seen.insert(i.id)
            result.append(i)
        }
        return result
    }
}

// MARK: - NotificationItem/Row 保持与之前一致
// 请保留你现有的 NotificationItem 和 NotificationRowView 定义，或使用我之前发的版本。
