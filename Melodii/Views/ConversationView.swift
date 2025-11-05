//
//  ConversationView.swift
//  Melodii
//
//  优化的单个会话页：加载消息、实时订阅、发送消息、已读回执
//  新增：动画效果、优化布局、更好的错误处理
//

import SwiftUI
import PhotosUI
import UIKit

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

    // 语音录制状态（用于按钮动画）
    @State private var isRecording = false

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
        ZStack {
            // 主背景渐变
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGray6).opacity(0.2),
                    Color.blue.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 装饰性气泡
            GeometryReader { geometry in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.08), Color.clear],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geometry.size.width - 100, y: -150)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.06), Color.clear],
                            center: .bottomLeading,
                            startRadius: 0,
                            endRadius: 250
                        )
                    )
                    .frame(width: 350, height: 350)
                    .offset(x: -100, y: geometry.size.height - 150)
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // 头像 - 支持真实头像
            NavigationLink(destination: UserProfileView(user: otherUser)) {
                Group {
                    if let avatarURL = otherUser.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 42, height: 42)
                                    .overlay(ProgressView().scaleEffect(0.6))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 42, height: 42)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2
                                            )
                                    )
                            case .failure:
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
                            @unknown default:
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 42, height: 42)
                            }
                        }
                    } else {
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
                    }
                }
                .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
                .overlay(
                    // 在线状态指示器
                    Circle()
                        .fill(otherUser.isOnline ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                        .offset(x: 15, y: 15)
                        .shadow(color: otherUser.isOnline ? Color.green.opacity(0.5) : Color.clear, radius: 4)
                )
            }
            .buttonStyle(.plain)

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
                                },
                                onImageTap: { url in
                                    fullscreenImageUrl = url
                                    showFullscreenImage = true
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
            // 快捷表情按钮栏
            quickEmojiBar
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)

            Divider()

            // 主输入区域
            HStack(spacing: 12) {
                // 左侧功能按钮 - 更多选项
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showEmojiPicker.toggle()
                    }
                    isInputFocused = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray6))
                            .frame(width: 42, height: 42)

                        Image(systemName: "app.grid.2x2")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                }

                // 输入框
                HStack(spacing: 8) {
                    TextField("发送消息", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .onChange(of: inputText) { _, newValue in
                            handleTyping(newValue)
                        }

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 16))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // 右侧圆形按钮组
                HStack(spacing: 8) {
                    // 语音按钮
                    Button {
                        // TODO: 实现语音录制
                        isRecording.toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray6))
                                .frame(width: 42, height: 42)

                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                        }
                    }
                    .scaleEffect(isRecording ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)

                    // 表情按钮
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showEmojiPicker.toggle()
                        }
                        isInputFocused = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(showEmojiPicker ? Color.blue.opacity(0.15) : Color(.systemGray6))
                                .frame(width: 42, height: 42)

                            Image(systemName: showEmojiPicker ? "face.smiling.fill" : "face.smiling")
                                .font(.system(size: 18))
                                .foregroundStyle(showEmojiPicker ? .blue : .primary)
                        }
                    }

                    // 加号按钮 - 图片和更多
                    PhotosPicker(selection: $selectedPhotoItem, matching: .any(of: [.images, .videos])) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray6))
                                .frame(width: 42, height: 42)

                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .disabled(isUploadingImage)
                    .onChange(of: selectedPhotoItem) { _, newValue in
                        if newValue != nil {
                            Task { await handleMediaSelection() }
                        }
                    }
                }

                // 发送按钮（仅在有文字时显示）
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await send() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.5, green: 0.4, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)
                                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)

                            if isSending {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .disabled(isSending)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            // 表情选择器
            if showEmojiPicker {
                EmojiPickerView(onSelect: { emoji in
                    inputText += emoji
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showEmojiPicker = false
                    }
                })
                .frame(height: 280)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Quick Emoji Bar

    private var quickEmojiBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickEmojis, id: \.text) { emoji in
                    Button {
                        sendQuickEmoji(emoji.text)
                    } label: {
                        HStack(spacing: 6) {
                            Text(emoji.emoji)
                                .font(.title3)
                            Text(emoji.text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(QuickEmojiButtonStyle())
                }
            }
            .padding(.horizontal, 12)
        }
    }

    // 快捷表情数据
    private let quickEmojis: [(emoji: String, text: String)] = [
        ("⭐", "晚上好"),
        ("😘", "比个心"),
        ("👍", "赞"),
        ("😂", "搞脸"),
        ("🌹", "玫瑰"),
        ("❤️", "爱你"),
        ("🎉", "庆祝"),
        ("👋", "你好"),
        ("😊", "微笑"),
        ("🔥", "火"),
        ("💯", "完美"),
        ("👏", "鼓掌")
    ]

    // 发送快捷表情
    private func sendQuickEmoji(_ text: String) {
        // 添加触觉反馈
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        inputText = text
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒延迟
            await send()
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

    // 处理图片和视频选择
    private func handleMediaSelection() async {
        guard let item = selectedPhotoItem else { return }

        isUploadingImage = true
        uploadProgress = 0

        defer {
            isUploadingImage = false
            selectedPhotoItem = nil
        }

        do {
            // 判断是图片还是视频
            let supportedTypes = item.supportedContentTypes
            let isVideo = supportedTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) })

            // 加载媒体数据
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "MediaLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法加载媒体文件"])
            }

            uploadProgress = 0.3

            // 上传媒体文件
            guard let myId = authService.currentUser?.id else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先登录"])
            }

            let mimeType: String
            let folder: String
            let messageType: MessageType

            if isVideo {
                mimeType = "video/mp4"
                folder = "messages/\(myId)/videos"
                messageType = .image // 暂时使用 .image，后续可以扩展 MessageType 添加 .video
            } else {
                mimeType = "image/jpeg"
                folder = "messages/\(myId)/images"
                messageType = .image
            }

            // 图片在发送前压缩，视频保持原样但提供体积提示与真实进度
            var uploadData = data
            if !isVideo, let image = UIImage(data: data) {
                uploadData = try await compressImageForMessage(image: image, maxBytes: 4 * 1024 * 1024)
            }

            let mediaUrl = try await supabaseService.uploadPostMediaWithProgress(
                data: uploadData,
                mime: mimeType,
                fileName: nil,
                folder: folder,
                bucket: "media",
                isPublic: true,
                onProgress: { p in
                    DispatchQueue.main.async { self.uploadProgress = max(0.05, min(0.95, p)) }
                }
            )

            uploadProgress = 0.7

            // 发送媒体消息
            await sendMediaMessage(mediaUrl: mediaUrl, messageType: messageType)

            uploadProgress = 1.0

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            print("❌ 媒体文件上传失败: \(error)")
            let msg = error.localizedDescription
            if msg.contains("maximum allowed size") || (error as NSError).code == 413 {
                errorMessage = "上传失败：文件过大。请压缩后再试。建议照片≤4MB、视频≤25MB。"
            } else {
                errorMessage = "上传失败: \(msg)"
            }
            showError = true

            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - 压缩辅助（仅会话内使用）
    private func compressImageForMessage(image: UIImage, maxBytes: Int) async throws -> Data {
        var quality: CGFloat = 0.85
        var data = image.jpegData(compressionQuality: quality)
        if let d = data, d.count <= maxBytes { return d }
        while quality > 0.4 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
            if let d = data, d.count <= maxBytes { return d }
        }
        // 缩放
        let targetMaxSide: CGFloat = 1280
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale = min(1.0, targetMaxSide / maxSide)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let scaledImage = scaled, let scaledData = scaledImage.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "Compression", code: -1, userInfo: [NSLocalizedDescriptionKey: "图片压缩失败"])
        }
        if scaledData.count <= maxBytes { return scaledData }
        if let finalData = scaledImage.jpegData(compressionQuality: 0.5), finalData.count <= maxBytes { return finalData }
        throw NSError(domain: "Compression", code: 413, userInfo: [NSLocalizedDescriptionKey: "图片过大，压缩后仍超过上限（≤4MB）"])
    }

    // 发送媒体消息（图片或视频）
    private func sendMediaMessage(mediaUrl: String, messageType: MessageType) async {
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
                content: mediaUrl,  // 媒体URL作为content
                messageType: messageType
            )

            // 成功反馈
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            // 立即追加本地乐观媒体消息，提升即时感
            let optimistic = Message(
                id: "local-media-" + UUID().uuidString,
                conversationId: conversation.id,
                senderId: myId,
                receiverId: otherUser.id,
                sender: authService.currentUser,
                content: mediaUrl,
                messageType: messageType,
                isRead: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(optimistic)
                }
            }
        } catch {
            print("❌ 发送媒体消息失败: \(error)")
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
                    // 更新应用badge
                    await NotificationManager.shared.updateBadgeCount(UnreadCenter.shared.unreadMessages + UnreadCenter.shared.unreadNotifications)
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
                // 仅移除与回流消息匹配的待发送项（避免误清空）
                if let myId = authService.currentUser?.id, msg.senderId == myId {
                    if let idx = pendingMessages.firstIndex(where: { $0.content == msg.content }) {
                        withAnimation { pendingMessages.remove(at: idx) }
                    }
                }

                // 去重：若已有本地乐观消息，则替换，否则追加
                if let dupIdx = messages.firstIndex(where: {
                    $0.id == msg.id ||
                    ($0.senderId == msg.senderId && $0.content == msg.content && $0.id.hasPrefix("local-") && abs($0.createdAt.timeIntervalSince(msg.createdAt)) < 10)
                }) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        messages[dupIdx] = msg
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        messages.append(msg)
                    }
                }

                if let myId = authService.currentUser?.id, msg.receiverId == myId {
                    // 对方发来的消息，立即标记已读并减少未读计数
                    try? await supabaseService.markMessageAsRead(messageId: msg.id)
                    UnreadCenter.shared.decrementMessages(1)

                    // 更新应用badge
                    Task {
                        await NotificationManager.shared.updateBadgeCount(UnreadCenter.shared.unreadMessages + UnreadCenter.shared.unreadNotifications)
                    }

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
                isSending = false // 发送成功，重置状态
            }

            // 发送成功：移除待发送气泡并追加本地乐观消息，避免短暂消失
            withAnimation {
                pendingMessages.removeAll { $0.id == pendingId }
            }
            let optimistic = Message(
                id: "local-" + pendingId,
                conversationId: conversation.id,
                senderId: myId,
                receiverId: otherUser.id,
                sender: authService.currentUser,
                content: text,
                messageType: .text,
                isRead: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(optimistic)
            }
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
                isSending = false // 发送失败，也要重置状态
            }
        }
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
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemGray6))
                                    ProgressView()
                                }
                                .frame(width: 200, height: 150)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 200, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .onTapGesture {
                                        onImageTap?(message.content)
                                    }
                            case .failure:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemGray6))
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .font(.title2)
                                        Text("加载失败")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .frame(width: 200, height: 150)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .shadow(
                            color: isMe ? Color.blue.opacity(0.25) : Color.black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 3
                        )
                    } else {
                        // 文本消息
                        Text(message.content)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .foregroundColor(isMe ? .white : .primary)
                            .background(
                                Group {
                                    if isMe {
                                        ZStack {
                                            // 外层光晕效果
                                            LinearGradient(
                                                colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.5, green: 0.4, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                            .blur(radius: 8)
                                            .opacity(0.3)

                                            // 主体渐变
                                            LinearGradient(
                                                colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.5, green: 0.4, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        }
                                    } else {
                                        ZStack {
                                            // 添加微妙的边框光泽效果
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color(.systemGray6))

                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.5), Color.clear],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 0.5
                                                )
                                        }
                                    }
                                }
                            )
                            .clipShape(
                                RoundedRectangle(cornerRadius: 20)
                            )
                            .shadow(
                                color: isMe ? Color.blue.opacity(0.25) : Color.black.opacity(0.05),
                                radius: isMe ? 10 : 3,
                                x: 0,
                                y: isMe ? 4 : 1
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
    @State private var opacity: Double = 0.7
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 10) {
                    Text(content)
                        .font(.body)

                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(
                    ZStack {
                        // 主体渐变
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.65), Color(red: 0.5, green: 0.4, blue: 1.0).opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        // 闪烁效果
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.3), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: shimmerOffset)
                        .blur(radius: 3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .opacity(opacity)
                .shadow(color: Color.blue.opacity(0.15), radius: 8, x: 0, y: 3)

                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("发送中")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            // 呼吸效果
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                opacity = 0.95
            }

            // 闪烁效果
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
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

// MARK: - Quick Emoji Button Style

struct QuickEmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
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
