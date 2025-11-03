import SwiftUI

struct ConversationsView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if !authService.isAuthenticated {
                    ContentUnavailableView("未登录", systemImage: "message", description: Text("登录后可查看私信"))
                } else if isLoading && conversations.isEmpty {
                    ProgressView("加载中…")
                } else if conversations.isEmpty {
                    ContentUnavailableView("暂无会话", systemImage: "message.badge", description: Text("当你和其他用户互发消息时，会话会出现在这里"))
                } else {
                    List {
                        ForEach(conversations) { conv in
                            NavigationLink {
                                ChatView(conversationId: conv.id)
                            } label: {
                                ConversationRow(conv: conv, currentUserId: authService.currentUser?.id ?? "")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadConversations() }
                }
            }
            .navigationTitle("消息")
            .task {
                if authService.isAuthenticated {
                    await loadConversations()
                    // 订阅会话变化（可选，用于 last_message_at 更新）
                    if let uid = authService.currentUser?.id {
                        await RealtimeService.shared.subscribeToConversations(userId: uid) { [weak self] in
                            Task { await self?.loadConversations() }
                        }
                    }
                }
            }
            .onDisappear {
                Task { await RealtimeService.shared.unsubscribeConversations() }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: { Text(alertMessage) }
        }
    }

    private func loadConversations() async {
        guard let uid = authService.currentUser?.id else { return }
        isLoading = true
        do {
            conversations = try await supabaseService.fetchConversations(userId: uid)
        } catch {
            alertMessage = "加载失败：\(error.localizedDescription)"
            showAlert = true
        }
        isLoading = false
    }
}

private struct ConversationRow: View {
    let conv: Conversation
    let currentUserId: String

    var otherUser: User? {
        conv.getOtherUser(currentUserId: currentUserId)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(
                    Text((otherUser?.nickname ?? "用户").prefix(1))
                        .font(.headline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(otherUser?.nickname ?? "用户")
                    .font(.headline)

                if let text = conv.lastMessage?.content {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(conv.lastMessageAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
