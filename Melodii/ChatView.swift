import SwiftUI

struct ChatView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    let conversationId: String

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg, isMine: msg.senderId == authService.currentUser?.id)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("输入消息…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                    }
                }
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("聊天")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await initialLoad()
            await subscribe()
        }
        .onDisappear {
            Task { await RealtimeService.shared.unsubscribeMessages(conversationId: conversationId) }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    private func initialLoad() async {
        isLoading = true
        do {
            messages = try await supabaseService.fetchMessages(conversationId: conversationId, limit: 50, offset: 0)
            // 进入页面后标记对方发给我的未读为已读
            if let uid = authService.currentUser?.id {
                try? await supabaseService.markConversationAsRead(conversationId: conversationId, userId: uid)
            }
        } catch {
            alertMessage = "加载消息失败：\(error.localizedDescription)"
            showAlert = true
        }
        isLoading = false
    }

    private func subscribe() async {
        await RealtimeService.shared.subscribeToMessages(
            conversationId: conversationId,
            onInsert: { [weak self] newMsg in
                guard let self else { return }
                Task {
                    // 加载发送者信息以显示头像/昵称
                    var enriched = newMsg
                    let msgs = try? await self.supabaseService.fetchMessages(conversationId: self.conversationId, limit: 1, offset: max(0, self.messages.count - 1))
                    // 简化：直接补上 sender（也可单独查 user）
                    if let sender = try? await self.supabaseService.fetchUser(id: newMsg.senderId) {
                        enriched.sender = sender
                    }
                    self.messages.append(enriched)

                    // 如果是发给我，标记已读
                    if let uid = self.authService.currentUser?.id, newMsg.receiverId == uid {
                        try? await self.supabaseService.markMessageAsRead(messageId: newMsg.id)
                    }
                }
            },
            onUpdate: { [weak self] updated in
                guard let self else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == updated.id }) {
                    self.messages[idx] = updated
                }
            }
        )
    }

    private func send() async {
        guard let uid = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        do {
            // 获取会话信息以确定对方ID
            let conv = try await supabaseService.fetchConversation(id: conversationId, currentUserId: uid)
            guard let other = conv.getOtherUser(currentUserId: uid) else { throw NSError(domain: "Chat", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取对方信息"]) }

            let message = try await supabaseService.sendMessage(conversationId: conversationId, senderId: uid, receiverId: other.id, content: text, messageType: .text)
            messages.append(message)
            inputText = ""
        } catch {
            alertMessage = "发送失败：\(error.localizedDescription)"
            showAlert = true
        }
        isSending = false
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer() }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMine ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer() }
        }
    }
}
