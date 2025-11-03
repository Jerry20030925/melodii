//
//  ConversationView.swift
//  Melodii
//
//  优化的单个会话页：加载消息、实时订阅、发送消息、已读回执
//  新增：动画效果、优化布局、更好的错误处理
//

import SwiftUI
import PhotosUI

struct ConversationView: View {
    let conversation: Conversation
    let otherUser: User

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared

    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showError = false

    // 键盘控制
    @FocusState private var isInputFocused: Bool

    // 临时消息（发送中）
    @State private var pendingMessages: [PendingMessage] = []

    // 表情选择器
    @State private var showEmojiPicker = false

    // 输入状态
    @State private var isTyping = false
    @State private var typingTimer: Timer?

    // 连接状态
    @State private var isConnected = true

    // 图片选择
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadProgress: Double = 0
    @State private var fullscreenImageUrl: String?
    @State private var showFullscreenImage = false

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                messageList
                inputBarView
            }
        }
        .navigationTitle(otherUser.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
            await subscribeRealtime()
        }
        .onAppear {
            // 启动输入动画
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                typingAnimationPhase += 0.05
            }
        }
        .onDisappear {
            Task { await RealtimeService.shared.unsubscribeConversationMessages(conversationId: conversation.id) }
            typingTimer?.invalidate()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $showFullscreenImage) {
            if let imageUrl = fullscreenImageUrl {
                FullscreenImageViewer(urls: [imageUrl], isPresented: $showFullscreenImage, index: 0)
            }
        }
        .overlay(uploadProgressOverlay)
    }

    // MARK: - Background

    private var backgroundView: some View {
        let bgColors: [Color] = [
            Color(.systemBackground),
            Color(.systemGray6).opacity(0.3)
        ]
        return LinearGradient(colors: bgColors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.7), .pink.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 42, height: 42)
                .overlay(
                    Text(otherUser.initials)
                        .font(.headline)
                        .foregroundColor(.white)
                )
                .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(otherUser.nickname)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    // 连接状态指示
                    if !isConnected {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("连接中...")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if isTyping {
                        // 输入状态动画
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                    .offset(y: typingAnimationOffset(for: index))
                            }
                        }
                        Text("正在输入...")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    } else if let mid = otherUser.mid {
                        Text("MID: \(mid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // 输入动画偏移
    @State private var typingAnimationPhase = 0.0

    private func typingAnimationOffset(for index: Int) -> CGFloat {
        let phase = typingAnimationPhase + Double(index) * 0.3
        return sin(phase * .pi * 2) * 3
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else if messages.isEmpty && pendingMessages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messages) { msg in
                            MessageBubble(
                                message: msg,
                                isMe: msg.senderId == authService.currentUser?.id,
                                onDelete: {
                                    Task { await recallMessage(msg) }
                                },
                                onCopy: {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            )
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        // 显示待发送消息
                        ForEach(pendingMessages) { pending in
                            PendingMessageBubble(content: pending.content)
                                .id(pending.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: pendingMessages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onTapGesture {
                isInputFocused = false
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Text("开始聊天")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("发送第一条消息，开启对话吧")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Input Bar

    private var inputBarView: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // 图片按钮
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .disabled(isUploadingImage)
                .onChange(of: selectedPhotoItem) { _, newValue in
                    if newValue != nil {
                        Task { await handleImageSelection() }
                    }
                }

                // 表情按钮
                Button {
                    showEmojiPicker.toggle()
                    isInputFocused = false
                } label: {
                    Image(systemName: showEmojiPicker ? "face.smiling.fill" : "face.smiling")
                        .font(.title3)
                        .foregroundStyle(showEmojiPicker ? .blue : .secondary)
                }

                // 输入框
                TextField("输入消息...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .onChange(of: inputText) { _, newValue in
                        handleTyping(newValue)
                    }

                // 发送按钮
                Button {
                    Task { await send() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AnyShapeStyle(Color(.systemGray5))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            )
                            .frame(width: 40, height: 40)

                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .scaleEffect(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.9 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // 表情选择器
            if showEmojiPicker {
                EmojiPickerView(onSelect: { emoji in
                    inputText += emoji
                    showEmojiPicker = false
                })
                .frame(height: 280)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Upload Progress Overlay

    private var uploadProgressOverlay: some View {
        Group {
            if isUploadingImage {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView(value: uploadProgress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .padding(.bottom, 80)
                }
            }
        }
    }

    // 处理输入状态
    private func handleTyping(_ text: String) {
        typingTimer?.invalidate()

        if !text.isEmpty {
            // TODO: 发送输入状态到服务器
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                // 2秒后停止输入状态
            }
        }
    }

    // 处理图片选择
    private func handleImageSelection() async {
        guard let item = selectedPhotoItem else { return }

        isUploadingImage = true
        uploadProgress = 0

        defer {
            isUploadingImage = false
            selectedPhotoItem = nil
        }

        do {
            // 加载图片数据
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "ImageLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载图片"])
            }

            uploadProgress = 0.3

            // 上传图片
            guard let myId = authService.currentUser?.id else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
            }

            let imageUrl = try await supabaseService.uploadPostMedia(
                data: data,
                mime: "image/jpeg",
                fileName: nil,
                folder: "messages/\(myId)/images"
            )

            uploadProgress = 0.7

            // 发送图片消息
            await sendImageMessage(imageUrl: imageUrl)

            uploadProgress = 1.0

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            print("❌ 图片上传失败: \(error)")
            errorMessage = "图片上传失败: \(error.localizedDescription)"
            showError = true

            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // 发送图片消息
    private func sendImageMessage(imageUrl: String) async {
        guard let myId = authService.currentUser?.id else {
            errorMessage = "请先登录"
            showError = true
            return
        }

        guard !otherUser.id.isEmpty else {
            errorMessage = "无法获取对方信息，请返回重试"
            showError = true
            return
        }

        do {
            _ = try await supabaseService.sendMessage(
                conversationId: conversation.id,
                senderId: myId,
                receiverId: otherUser.id,
                content: imageUrl,  // 图片URL作为content
                messageType: .image
            )

            // 成功反馈
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch {
            print("❌ 发送图片消息失败: \(error)")
            errorMessage = "发送失败: \(error.localizedDescription)"
            showError = true

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Data Loading

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            messages = try await supabaseService.fetchMessages(conversationId: conversation.id, limit: 50, offset: 0)

            // 将未读消息标记为已读（我是接收方的消息）
            if let myId = authService.currentUser?.id {
                let unread = messages.filter { $0.receiverId == myId && !$0.isRead }
                for m in unread {
                    try? await supabaseService.markMessageAsRead(messageId: m.id)
                }
                if !unread.isEmpty {
                    UnreadCenter.shared.decrementMessages(unread.count)
                }
            }
        } catch {
            print("❌ 加载消息失败: \(error)")
            errorMessage = "加载消息失败"
            showError = true
        }
    }

    private func subscribeRealtime() async {
        await RealtimeService.shared.subscribeToConversationMessages(conversationId: conversation.id) { msg in
            Task { @MainActor in
                // 移除对应的待发送消息（如果存在）
                pendingMessages.removeAll()

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(msg)
                }

                if let myId = authService.currentUser?.id, msg.receiverId == myId {
                    // 对方发来的消息，立即标记已读并减少未读计数
                    try? await supabaseService.markMessageAsRead(messageId: msg.id)
                    UnreadCenter.shared.decrementMessages(1)

                    // 触觉反馈
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    private func send() async {
        guard let myId = authService.currentUser?.id else {
            errorMessage = "请先登录"
            showError = true
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 验证对方用户信息
        guard !otherUser.id.isEmpty else {
            errorMessage = "无法获取对方信息，请返回重试"
            showError = true
            return
        }

        // 添加到待发送列表
        let pendingId = UUID().uuidString
        let pending = PendingMessage(id: pendingId, content: text)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingMessages.append(pending)
        }

        inputText = ""
        isSending = true

        do {
            _ = try await supabaseService.sendMessage(
                conversationId: conversation.id,
                senderId: myId,
                receiverId: otherUser.id,
                content: text,
                messageType: .text
            )

            // 成功反馈
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            // 发送成功后，消息会通过 Realtime 回流到列表
        } catch {
            // 发送失败，移除待发送消息
            withAnimation {
                pendingMessages.removeAll { $0.id == pendingId }
            }

            print("❌ 发送消息失败: \(error)")
            errorMessage = "发送失败: \(error.localizedDescription)"
            showError = true

            // 恢复输入文本
            inputText = text

            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        isSending = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            if let msg = messages.last {
                proxy.scrollTo(msg.id, anchor: .bottom)
            } else if let pending = pendingMessages.last {
                proxy.scrollTo(pending.id, anchor: .bottom)
            }
        }
    }

    // 撤回消息
    private func recallMessage(_ message: Message) async {
        do {
            // TODO: 调用服务器API撤回消息
            // try await supabaseService.recallMessage(messageId: message.id)

            // 从本地列表移除
            withAnimation {
                messages.removeAll { $0.id == message.id }
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = "撤回失败: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Message Extensions

extension Message {
    /// 是否可以撤回（发送后2分钟内）
    var canRecall: Bool {
        let elapsed = Date().timeIntervalSince(createdAt)
        return elapsed < 120 // 2分钟 = 120秒
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: Message
    let isMe: Bool
    let onDelete: (() -> Void)?
    let onCopy: (() -> Void)?
    let onImageTap: ((String) -> Void)?

    init(message: Message, isMe: Bool, onDelete: (() -> Void)? = nil, onCopy: (() -> Void)? = nil, onImageTap: ((String) -> Void)? = nil) {
        self.message = message
        self.isMe = isMe
        self.onDelete = onDelete
        self.onCopy = onCopy
        self.onImageTap = onImageTap
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // 根据消息类型显示不同内容
                Group {
                    if message.messageType == .image {
                        // 图片消息
                        AsyncImage(url: URL(string: message.content)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 200, height: 150)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 200, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                VStack {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.title)
                                    Text("加载失败")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .frame(width: 200, height: 150)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .shadow(
                            color: isMe ? Color.blue.opacity(0.2) : Color.black.opacity(0.05),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                    } else {
                        // 文本消息
                        Text(message.content)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .foregroundColor(isMe ? .white : .primary)
                            .background(
                                Group {
                                    if isMe {
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        Color(.systemGray5)
                                    }
                                }
                            )
                            .clipShape(
                                BubbleShape(isMe: isMe)
                            )
                            .shadow(
                                color: isMe ? Color.blue.opacity(0.2) : Color.black.opacity(0.05),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                    }
                }
                .contextMenu {
                    // 复制按钮（仅限文本消息）
                    if message.messageType == .text {
                        Button {
                            UIPasteboard.general.string = message.content
                            onCopy?()
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }

                    // 撤回按钮（仅限自己的消息且发送不超过2分钟）
                    if isMe && message.canRecall {
                        Button(role: .destructive) {
                            onDelete?()
                        } label: {
                            Label("撤回", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                Text(message.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Pending Message Bubble

private struct PendingMessageBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(content)
                        .font(.body)

                    ProgressView()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(BubbleShape(isMe: true))

                Text("发送中...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Bubble Shape

private struct BubbleShape: Shape {
    let isMe: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tailSize: CGFloat = 8

        var path = Path()

        if isMe {
            // 右侧气泡（我发送的）
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius - tailSize, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius - tailSize, y: rect.minY + radius),
                       radius: radius,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(0),
                       clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX - tailSize, y: rect.maxY - radius - tailSize))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - tailSize, y: rect.maxY - tailSize))
            path.addArc(center: CGPoint(x: rect.maxX - radius - tailSize, y: rect.maxY - radius),
                       radius: radius,
                       startAngle: .degrees(0),
                       endAngle: .degrees(90),
                       clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                       radius: radius,
                       startAngle: .degrees(90),
                       endAngle: .degrees(180),
                       clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                       radius: radius,
                       startAngle: .degrees(180),
                       endAngle: .degrees(270),
                       clockwise: false)
        } else {
            // 左侧气泡（对方发送的）
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + tailSize, y: rect.maxY - tailSize))
            path.addLine(to: CGPoint(x: rect.minX + tailSize, y: rect.maxY - radius - tailSize))
            path.addArc(center: CGPoint(x: rect.minX + radius + tailSize, y: rect.maxY - radius),
                       radius: radius,
                       startAngle: .degrees(180),
                       endAngle: .degrees(90),
                       clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                       radius: radius,
                       startAngle: .degrees(90),
                       endAngle: .degrees(0),
                       clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                       radius: radius,
                       startAngle: .degrees(0),
                       endAngle: .degrees(-90),
                       clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + radius + tailSize, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + radius + tailSize, y: rect.minY + radius),
                       radius: radius,
                       startAngle: .degrees(-90),
                       endAngle: .degrees(180),
                       clockwise: true)
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Pending Message Model

private struct PendingMessage: Identifiable {
    let id: String
    let content: String
}

// MARK: - Emoji Picker

private struct EmojiPickerView: View {
    let onSelect: (String) -> Void

    private let emojiCategories: [EmojiCategory] = [
        EmojiCategory(name: "笑脸", emojis: ["😀", "😃", "😄", "😁", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚"]),
        EmojiCategory(name: "手势", emojis: ["👋", "🤚", "🖐", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙", "👈", "👉", "👆", "🖕", "👇", "☝️", "👍", "👎", "✊", "👊", "🤛", "🤜"]),
        EmojiCategory(name: "爱心", emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝"]),
        EmojiCategory(name: "符号", emojis: ["✨", "💫", "⭐", "🌟", "✅", "❌", "⚠️", "🔥", "💯", "👏", "🎉", "🎊", "🎈"]),
    ]

    @State private var selectedCategory = 0

    var body: some View {
        VStack(spacing: 0) {
            // 类别选择器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(emojiCategories.enumerated()), id: \.offset) { index, category in
                        Button {
                            selectedCategory = index
                        } label: {
                            Text(category.name)
                                .font(.subheadline)
                                .fontWeight(selectedCategory == index ? .semibold : .regular)
                                .foregroundStyle(selectedCategory == index ? .blue : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedCategory == index
                                    ? Color.blue.opacity(0.1)
                                    : Color.clear
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            // 表情网格
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 8),
                    spacing: 12
                ) {
                    ForEach(emojiCategories[selectedCategory].emojis, id: \.self) { emoji in
                        Button {
                            onSelect(emoji)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(emoji)
                                .font(.largeTitle)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGray6))
    }
}

private struct EmojiCategory {
    let name: String
    let emojis: [String]
}

#Preview {
    NavigationStack {
        ConversationView(
            conversation: Conversation(
                id: "test",
                participant1Id: "user1",
                participant2Id: "user2",
                lastMessageAt: Date(),
                createdAt: Date(),
                updatedAt: Date()
            ),
            otherUser: User(id: "user2", nickname: "测试用户")
        )
    }
}
