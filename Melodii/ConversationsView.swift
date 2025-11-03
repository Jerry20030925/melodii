//
//  ConversationsView.swift
//  Melodii
//
//  会话列表页：展示最近会话、进入单聊、实时新消息更新与未读角标联动
//

import SwiftUI
import Combine

struct ConversationsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared
    @ObservedObject private var realtimeService = RealtimeService.shared

    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if !authService.isAuthenticated {
                    ContentUnavailableView(
                        "未登录",
                        systemImage: "message",
                        description: Text("登录后可查看消息")
                    )
                } else if isLoading && conversations.isEmpty {
                    ProgressView("加载会话中…")
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        "暂无会话",
                        systemImage: "message",
                        description: Text("和朋友打个招呼吧")
                    )
                } else {
                    List {
                        ForEach(conversations) { conv in
                            NavigationLink {
                                if let me = authService.currentUser {
                                    ConversationView(conversation: conv, otherUser: otherUser(in: conv, me: me))
                                } else {
                                    Text("请先登录")
                                }
                            } label: {
                                ConversationRow(conversation: conv, currentUserId: authService.currentUser?.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadConversations()
                    }
                }
            }
            .navigationTitle("消息")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadConversations() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if authService.isAuthenticated && conversations.isEmpty {
                    await loadConversations()
                    await subscribeRealtime()
                }
            }
            .onDisappear {
                Task {
                    await RealtimeService.shared.unsubscribeConversations()
                }
            }
            .onReceive(realtimeService.$newMessage.compactMap { $0 }) { msg in
                // 收到新消息时，移动对应会话到顶部；若不存在则刷新列表
                if let idx = conversations.firstIndex(where: { $0.id == msg.conversationId }) {
                    let conv = conversations.remove(at: idx)
                    conversations.insert(conv, at: 0)
                } else {
                    Task { await loadConversations() }
                }
                // 未读数处理：如果我是接收者，+1
                if let uid = authService.currentUser?.id, msg.receiverId == uid {
                    UnreadCenter.shared.incrementMessages()
                }
                // 清空一次性通知
                realtimeService.clearNewMessage()
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func otherUser(in conv: Conversation, me: User) -> User {
        if conv.participant1Id == me.id { return conv.participant2 ?? User(id: conv.participant2Id, nickname: "用户") }
        else { return conv.participant1 ?? User(id: conv.participant1Id, nickname: "用户") }
    }

    private func loadConversations() async {
        guard let uid = authService.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await supabaseService.fetchConversations(userId: uid)
        } catch {
            errorMessage = "加载会话失败：\(error.localizedDescription)"
            showError = true
        }
    }

    private func subscribeRealtime() async {
        guard let uid = authService.currentUser?.id else { return }
        // 使用新增的会话级订阅：收到任何与我相关的新消息
        await RealtimeService.shared.subscribeToConversations(userId: uid) { msg in
            Task { @MainActor in
                if let idx = conversations.firstIndex(where: { $0.id == msg.conversationId }) {
                    let conv = conversations.remove(at: idx)
                    conversations.insert(conv, at: 0)
                } else {
                    await loadConversations()
                }
                if msg.receiverId == uid {
                    UnreadCenter.shared.incrementMessages()
                }
            }
        }
    }
}

// MARK: - Conversation Row

private struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: String?

    private var other: User? {
        if let me = currentUserId {
            return (conversation.participant1Id == me) ? conversation.participant2 : conversation.participant1
        }
        return conversation.participant1 ?? conversation.participant2
    }

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Text((other?.initials ?? "用"))
                        .font(.headline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(other?.nickname ?? "用户")
                    .font(.headline)
                // lastMessageAt 是非可选 Date，直接使用
                Text(conversation.lastMessageAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
