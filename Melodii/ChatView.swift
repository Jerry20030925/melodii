//
//  ChatView.swift
//  Melodii
//
//  Created by Assistant on 31/10/2025.
//

import SwiftUI
import AVFoundation
import PhotosUI

struct ChatView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var realtimeMessaging = RealtimeMessagingService.shared

    let conversationId: String
    let otherUserId: String  // 添加对方用户ID参数

    @State private var messages: [EnhancedMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    // 分页（历史消息）
    @State private var pageSize: Int = 50
    @State private var loadedCount: Int = 0
    @State private var hasMore: Bool = true
    @State private var isLoadingMore: Bool = false

    // 媒体选择/上传
    @State private var showingPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploading = false

    // 语音录制
    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    
    // 输入状态
    @State private var typingTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // 顶部加载更多
                        if hasMore {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView().padding(.vertical, 8)
                                } else {
                                    Button {
                                        Task { await loadMoreHistory(scrollProxy: proxy) }
                                    } label: {
                                        Text("加载更早的消息")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                Spacer()
                            }
                            .id("historyLoader")
                        }

                        ForEach(messages) { msg in
                            EnhancedMessageBubble(
                                message: msg, 
                                isMine: msg.senderId == authService.currentUser?.id
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                // Use the two-parameter iOS 17+ signature explicitly to avoid overload ambiguity
                .onChange(of: messages.count) { _, _ in
                    if let lastId = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            inputBar
        }
        .navigationTitle("聊天")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await initialLoad()
            await realtimeMessaging.subscribeToConversation(conversationId)
        }
        .onReceive(realtimeMessaging.$conversations) { conversations in
            if let conversationMessages = conversations[conversationId] {
                messages = conversationMessages.sorted { $0.createdAt < $1.createdAt }
            }
        }
        .onDisappear {
            realtimeMessaging.unsubscribeFromConversation(conversationId)
            typingTimer?.invalidate()
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) {}
        } message: { Text(alertMessage) }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("发送照片", systemImage: "photo.on.rectangle")
                }

                if isRecording {
                    Button(role: .destructive) {
                        Task { await stopAndSendVoice() }
                    } label: {
                        Label("停止并发送语音", systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        Task { await startRecording() }
                    } label: {
                        Label("开始录音", systemImage: "mic")
                    }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $photoPickerItem, matching: .images)

            TextField("输入消息…", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onChange(of: inputText) { _, newValue in
                    handleTyping(newValue)
                }

            if isUploading {
                ProgressView().frame(width: 20, height: 20)
            }

            Button {
                Task { await sendText() }
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
        // Two-parameter iOS 17+ signature
        .onChange(of: photoPickerItem) { _, newValue in
            if newValue != nil {
                Task { await handlePickedPhoto() }
            }
        }
    }

    // MARK: - Load & Subscribe

    private func initialLoad() async {
        isLoading = true
        do {
            let firstPage = try await supabaseService.fetchMessages(conversationId: conversationId, limit: pageSize, offset: 0)
            // Convert Message -> EnhancedMessage for initial load to match UI model
            let enhanced: [EnhancedMessage] = firstPage.map { m in
                EnhancedMessage(
                    id: m.id,
                    conversationId: m.conversationId,
                    senderId: m.senderId,
                    receiverId: m.receiverId,
                    sender: m.sender,
                    content: m.content,
                    messageType: m.messageType,
                    status: .sent,
                    isRead: m.isRead,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt
                )
            }
            messages = enhanced
            loadedCount = firstPage.count
            hasMore = firstPage.count == pageSize

            // 完全跳过标记已读操作，避免任何阻塞
            if let uid = authService.currentUser?.id {
                print("📱 跳过标记已读和未读计数更新，避免阻塞")
                // 完全不调用任何可能阻塞的操作
            }
        } catch {
            alertMessage = "加载消息失败：\(error.localizedDescription)"
            showAlert = true
        }
        isLoading = false
    }

    private func loadMoreHistory(scrollProxy: ScrollViewProxy) async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true

        let anchorId = messages.first?.id

        do {
            let nextPage = try await supabaseService.fetchMessages(conversationId: conversationId, limit: pageSize, offset: loadedCount)
            // Convert Message -> EnhancedMessage for pagination
            let enhancedNext: [EnhancedMessage] = nextPage.map { m in
                EnhancedMessage(
                    id: m.id,
                    conversationId: m.conversationId,
                    senderId: m.senderId,
                    receiverId: m.receiverId,
                    sender: m.sender,
                    content: m.content,
                    messageType: m.messageType,
                    status: .sent,
                    isRead: m.isRead,
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt
                )
            }
            messages.insert(contentsOf: enhancedNext, at: 0)
            loadedCount += nextPage.count
            hasMore = nextPage.count == pageSize

            if let anchorId {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut) {
                        scrollProxy.scrollTo(anchorId, anchor: .top)
                    }
                }
            }
        } catch {
            print("加载历史消息失败: \(error)")
        }

        isLoadingMore = false
    }

    // MARK: - 输入状态处理
    
    private func handleTyping(_ text: String) {
        guard let currentUserId = authService.currentUser?.id else { return }
        
        // 取消之前的计时器
        typingTimer?.invalidate()
        
        if !text.isEmpty {
            // 开始输入
            realtimeMessaging.startTyping(conversationId: conversationId, userId: currentUserId)
            
            // 设置停止输入的计时器
            typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                realtimeMessaging.stopTyping(conversationId: conversationId, userId: currentUserId)
            }
        } else {
            // 立即停止输入状态
            realtimeMessaging.stopTyping(conversationId: conversationId, userId: currentUserId)
        }
    }

    // MARK: - 优化的消息发送
    
    private func sendText() async {
        guard let currentUser = authService.currentUser else {
            await MainActor.run {
                alertMessage = "请先登录"
                showAlert = true
            }
            return
        }

        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // 防止重复发送
        guard !isSending else { return }

        await MainActor.run {
            isSending = true
        }

        let messageText = trimmedText
        await MainActor.run {
            inputText = "" // 立即清空输入框
        }

        // 停止输入状态
        realtimeMessaging.stopTyping(conversationId: conversationId, userId: currentUser.id)

        do {
            // 使用新的实时消息服务发送（支持乐观更新）
            _ = try await realtimeMessaging.sendMessage(
                conversationId: conversationId,
                senderId: currentUser.id,
                receiverId: otherUserId,
                content: messageText,
                messageType: .text
            )

            // 添加触觉反馈
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

        } catch {
            await MainActor.run {
                alertMessage = "发送失败：\(error.localizedDescription)"
                showAlert = true
                inputText = messageText // 恢复输入内容
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        await MainActor.run {
            isSending = false
        }
    }

    private func handlePickedPhoto() async {
        guard let item = photoPickerItem else { return }
        isUploading = true
        defer { isUploading = false; photoPickerItem = nil }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let urlString = try await supabaseService.uploadChatMedia(
                    data: data,
                    mime: "image/jpeg",
                    fileName: nil,
                    folder: "conversations/\(conversationId)/images",
                    bucket: "media",
                    isPublic: true
                )
                try await sendMediaMessage(urlString: urlString, type: .image)
            } else {
                throw NSError(domain: "Chat", code: -11, userInfo: [NSLocalizedDescriptionKey: "无法读取图片数据"])
            }
        } catch {
            alertMessage = "发送图片失败：\(error.localizedDescription)"
            showAlert = true
        }
    }

    private func startRecording() async {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)

            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            recorder = try AVAudioRecorder(url: tmpURL, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record()
            isRecording = true
        } catch {
            alertMessage = "无法开始录音：\(error.localizedDescription)"
            showAlert = true
        }
    }

    private func stopAndSendVoice() async {
        guard isRecording, let recorder else { return }
        recorder.stop()
        isRecording = false

        do {
            let data = try Data(contentsOf: recorder.url)
            let urlString = try await supabaseService.uploadChatMedia(
                data: data,
                mime: "audio/m4a",
                fileName: nil,
                folder: "conversations/\(conversationId)/voices",
                bucket: "media",
                isPublic: true
            )
            try await sendMediaMessage(urlString: urlString, type: .voice)
        } catch {
            alertMessage = "发送语音失败：\(error.localizedDescription)"
            showAlert = true
        }
    }

    private func sendMediaMessage(urlString: String, type: MessageType) async throws {
        guard let uid = authService.currentUser?.id else {
            throw NSError(domain: "Chat", code: -2, userInfo: [NSLocalizedDescriptionKey: "未登录"])
        }

        let message = try await supabaseService.sendMessage(
            conversationId: conversationId,
            senderId: uid,
            receiverId: otherUserId,  // 直接使用传入的otherUserId
            content: urlString,
            messageType: type
        )
        // Convert server Message -> EnhancedMessage before appending for consistency
        let enhanced = EnhancedMessage(
            id: message.id,
            conversationId: message.conversationId,
            senderId: message.senderId,
            receiverId: message.receiverId,
            sender: message.sender,
            content: message.content,
            messageType: message.messageType,
            status: .sent,
            isRead: message.isRead,
            createdAt: message.createdAt,
            updatedAt: message.updatedAt
        )
        messages.append(enhanced)
    }

    // MARK: - Helpers

    private func refreshUnreadMessagesCount() async {
        guard let uid = authService.currentUser?.id else { return }
        if let count = try? await supabaseService.getUnreadMessageCount(userId: uid) {
            UnreadCenter.shared.unreadMessages = count
        }
    }
}

// MARK: - Enhanced Message Bubble

private struct EnhancedMessageBubble: View {
    let message: EnhancedMessage
    let isMine: Bool

    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }
            
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                content
                    .background(bubbleBackground)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // 时间和状态
                HStack(spacing: 4) {
                    Text(formatTime(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if isMine {
                        messageStatusIcon
                    }
                }
                .padding(.horizontal, 4)
            }
            
            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
    
    private var bubbleBackground: some View {
        if isMine {
            AnyView(
                LinearGradient(
                    colors: message.status == .failed ? 
                        [Color.red.opacity(0.8), Color.red.opacity(0.6)] :
                        [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            AnyView(Color(.systemGray6))
        }
    }
    
    @ViewBuilder
    private var messageStatusIcon: some View {
        switch message.status {
        case .sending:
            ProgressView()
                .scaleEffect(0.6)
                .tint(.white.opacity(0.8))
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        case .delivered:
            Image(systemName: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        case .read:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.white)
        case .failed:
            Button {
                // 重试发送逻辑
            } label: {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var content: some View {
        switch message.messageType {
        case .text:
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .font(.body)
                .multilineTextAlignment(isMine ? .trailing : .leading)

        case .image:
            if let url = URL(string: message.content) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("加载中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(width: 200, height: 120)
                        
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 250, maxHeight: 300)
                            .clipped()
                            .onTapGesture {
                                // TODO: 添加图片全屏预览
                            }
                            
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text("图片加载失败")
                                .font(.caption)
                        }
                        .padding(16)
                        .frame(width: 200, height: 120)
                        
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("无效的图片链接")
                        .font(.caption)
                }
                .padding(16)
            }

        case .voice:
            HStack(spacing: 12) {
                Button {
                    Task { await togglePlay() }
                } label: {
                    Image(systemName: audioPlayer?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isMine ? .white : .blue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("语音消息")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // 语音波形效果
                    HStack(spacing: 2) {
                        ForEach(0..<8, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isMine ? Color.white.opacity(0.7) : Color.blue.opacity(0.7))
                                .frame(width: 3, height: CGFloat.random(in: 8...20))
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 150)

        case .system:
            Text(message.content)
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func togglePlay() async {
        guard let url = URL(string: message.content) else { return }
        
        if let player = audioPlayer, player.isPlaying {
            player.stop()
            audioPlayer = nil
        } else {
            do {
                let data = try Data(contentsOf: url)
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
            } catch {
                print("播放语音失败: \(error)")
            }
        }
    }
}

