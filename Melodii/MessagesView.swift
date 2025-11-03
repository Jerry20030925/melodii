//
//  MessagesView.swift
//  Melodii
//
//  Created by Jianwei Chen on 30/10/2025.
//

import SwiftUI

struct MessagesView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    @State private var selectedTab = 0
    @State private var unreadNotificationCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 自定义分段控制器
                Picker("消息类型", selection: $selectedTab) {
                    HStack {
                        Text("通知")
                        if unreadNotificationCount > 0 {
                            Text("(\(unreadNotificationCount))")
                                .foregroundStyle(.red)
                        }
                    }
                    .tag(0)

                    Text("私信")
                        .tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // 内容区域
                TabView(selection: $selectedTab) {
                    // 通知页面
                    NotificationsView()
                        .tag(0)

                    // 私信页面
                    DirectMessagesView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("消息")
            .task {
                await loadUnreadCount()
            }
            .onChange(of: selectedTab) { _, _ in
                if selectedTab == 0 {
                    Task { await loadUnreadCount() }
                }
            }
        }
    }

    private func loadUnreadCount() async {
        guard let userId = authService.currentUser?.id else {
            unreadNotificationCount = 0
            return
        }

        do {
            unreadNotificationCount = try await supabaseService.fetchUnreadNotificationCount(userId: userId)
        } catch {
            print("加载未读数失败: \(error)")
        }
    }
}

// MARK: - Direct Messages View

private struct DirectMessagesView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var realtimeService = RealtimeService.shared

    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        Group {
            if !authService.isAuthenticated {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("登录后可使用私信功能")
                )
            } else if conversations.isEmpty && !isLoading {
                ContentUnavailableView(
                    "还没有私信",
                    systemImage: "envelope.open",
                    description: Text("开始与其他用户聊天吧")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(conversations) { conversation in
                            if let otherUser = conversation.getOtherUser(currentUserId: authService.currentUser?.id ?? "") {
                                NavigationLink {
                                    ConversationView(conversation: conversation, otherUser: otherUser)
                                } label: {
                                    ConversationRowView(
                                        conversation: conversation,
                                        otherUser: otherUser
                                    )
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
                .refreshable {
                    await loadConversations()
                }
            }
        }
        .task {
            await loadConversations()
            if let uid = authService.currentUser?.id {
                await RealtimeService.shared.subscribeToConversations(userId: uid) { _ in
                    Task { await loadConversations() }
                }
            }
        }
        .onDisappear {
            Task { await RealtimeService.shared.unsubscribeConversations() }
        }
        .onReceive(realtimeService.$newMessage) { message in
            if message != nil {
                Task {
                    await loadConversations()
                    realtimeService.clearNewMessage()
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadConversations() async {
        guard let userId = authService.currentUser?.id else { return }

        isLoading = true

        do {
            conversations = try await supabaseService.fetchConversations(userId: userId)
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
            showError = true
            print("❌ 加载会话列表失败: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Conversation Row View

private struct ConversationRowView: View {
    let conversation: Conversation
    let otherUser: User

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Text(otherUser.initials)
                        .font(.title3)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherUser.nickname)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(conversation.lastMessageAt.timeAgoDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 最后一条消息预览
                if let lastMessage = conversation.lastMessage {
                    HStack(spacing: 4) {
                        Text(lastMessage.content)
                            .font(.subheadline)
                            .foregroundStyle(lastMessage.isRead ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer()

                        // 简单的未读红点（示例逻辑）
                        if !lastMessage.isRead {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        }
                    }
                } else {
                    Text("开始聊天...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    MessagesView()
}
