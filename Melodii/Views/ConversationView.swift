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
import AVFoundation
import Combine
import AVKit

struct ConversationView: View {
    let conversation: Conversation
    let otherUser: User

    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var unreadCenter = UnreadCenter.shared
    @ObservedObject private var errorHandler = ErrorHandler.shared
    @ObservedObject private var presence = PresenceManager.shared

    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showError = false

    // 键盘控制
    @FocusState private var isInputFocused: Bool
    @State private var showKeyboard: Bool = false

    // 临时消息（发送中）
    @State private var pendingMessages: [PendingMessage] = []

    // 表情和贴纸选择器
    @State private var showEmojiPicker = false

    // 输入状态
    @State private var isTyping = false
    @State private var typingTimer: Timer?

    // 连接状态
    @State private var isConnected = true
    
    // 缓存当前用户ID，避免重复查询
    @State private var currentUserId: String?
    // 当前活跃的会话ID（用于新建会话后切换订阅和加载）
    @State private var activeConversationId: String = ""

    // 图片选择
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var uploadProgress: Double = 0
    @State private var fullscreenImageUrl: String?
    @State private var showFullscreenImage = false
    // 视频全屏
    @State private var fullscreenVideoUrl: String?
    @State private var showFullscreenVideo = false
    // 附件面板显示控制
    @State private var showAttachmentPanel = false

    // 语音录制
    @State private var showVoiceRecorder = false
    @State private var isUploadingVoice = false
    @State private var useEnhancedInput = true
    
    // 输入动画状态
    @State private var typingAnimationPhase: TimeInterval = 0
    // 在线时长刷新时钟
    @State private var nowTick: Date = Date()

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
        .task(id: conversation.id) {
            // 缓存当前用户ID，提高UI渲染性能
            currentUserId = authService.currentUser?.id
            // 初始化活跃会话ID
            activeConversationId = conversation.id
            
            await loadMessages()
            await subscribeRealtime()
        }
        .onAppear {
            // 启动输入动画
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                typingAnimationPhase += 0.05
            }
            
            // 若未授权通知，主动请求一次（确保双方私信能收到系统通知）
            Task {
                let push = PushNotificationManager.shared
                if push.authorizationStatus == .notDetermined {
                    _ = await push.requestPermission()
                }
            }

            // 设置当前活跃对话以避免推送通知
            PushNotificationManager.shared.setActiveConversation(conversation.id)
            
            // 更新用户ID缓存
            currentUserId = authService.currentUser?.id
        }
        .onDisappear {
            Task { await RealtimeService.shared.unsubscribeConversationMessages(conversationId: conversation.id) }
            typingTimer?.invalidate()
            
            // 清除活跃对话状态
            PushNotificationManager.shared.clearActiveConversation()
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
        .sheet(isPresented: $showFullscreenVideo) {
            if let videoUrl = fullscreenVideoUrl {
                LegacyFullscreenMediaViewer(urls: [videoUrl], isPresented: $showFullscreenVideo, index: 0)
            }
        }
        .overlay(uploadProgressOverlay)
        .overlay {
            if showVoiceRecorder {
                VoiceRecorderView(isPresented: $showVoiceRecorder) { voiceURL in
                    Task { await sendVoiceMessage(voiceURL: voiceURL) }
                }
            }
        }
        // 当活跃会话ID变化（例如首次创建会话），重新订阅并加载消息
        .onChange(of: activeConversationId) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            Task {
                // 先取消旧的订阅
                if !oldValue.isEmpty {
                    await RealtimeService.shared.unsubscribeConversationMessages(conversationId: oldValue)
                }
                // 订阅新的会话，并拉取消息
                await subscribeRealtime()
                await loadMessages()
                PushNotificationManager.shared.setActiveConversation(newValue)
            }
        }
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
                    } else if presence.isUserOnline(otherUser.id) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(lastSeenText(since: otherUser.lastSeenAt ?? Date()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let lastSeen = otherUser.lastSeenAt {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 6, height: 6)
                        Text(lastSeenText(since: lastSeen))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let mid = otherUser.mid {
                        Text("MID: \(mid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
            HStack(spacing: 14) {
                Button { /* TODO: 语音通话 */ } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                Button { /* TODO: 视频通话 */ } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                NavigationLink(destination: UserProfileView(user: otherUser)) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            nowTick = date
        }
    }

    // 输入动画偏移
    private func typingAnimationOffset(for index: Int) -> CGFloat {
        let phase = typingAnimationPhase + Double(index) * 0.3
        return sin(phase * .pi * 2) * 3
    }

    // MARK: - 日期分隔条文案
    private func daySeparatorText(for message: Message, previous: Message?) -> String? {
        guard let prev = previous else { return dayLabel(for: message.createdAt) }
        let cal = Calendar.current
        if !cal.isDate(prev.createdAt, inSameDayAs: message.createdAt) {
            return dayLabel(for: message.createdAt)
        }
        return nil
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if cal.isDateInToday(date) { return "今天 \(timeText)" }
        if cal.isDateInYesterday(date) { return "昨天 \(timeText)" }

        let startDate = cal.startOfDay(for: date)
        let startNow = cal.startOfDay(for: now)
        let dayDiff = cal.dateComponents([.day], from: startDate, to: startNow).day ?? 0
        if dayDiff <= 7 {
            let weekdayMap = ["周日","周一","周二","周三","周四","周五","周六"]
            let weekdayIndex = (cal.component(.weekday, from: date) - 1 + 7) % 7
            let weekday = weekdayMap[weekdayIndex]
            return "\(weekday) — \(timeText)"
        } else {
            let mdFormatter = DateFormatter()
            mdFormatter.locale = Locale(identifier: "zh_CN")
            mdFormatter.dateFormat = "M月d日"
            let mdText = mdFormatter.string(from: date)
            return "\(mdText) — \(timeText)"
        }
    }
    
    

    private func lastSeenText(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let mins = Int(interval) / 60
        let hours = mins / 60
        let days = hours / 24
        if mins < 1 { return "刚刚在线" }
        if mins < 60 { return "\(mins) 分钟前在线" }
        if hours < 24 { return "\(hours) 小时前在线" }
        return "\(days) 天前在线"
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
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            if let sep = daySeparatorText(for: msg, previous: index > 0 ? messages[index - 1] : nil) {
                                HStack {
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 0.5)
                                    Text(sep)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemBackground).opacity(0.85))
                                        .clipShape(Capsule())
                                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 0.5)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                            }

                            MessageBubble(
                                message: msg,
                                isMe: msg.senderId == currentUserId,
                                onDelete: {
                                    Task { await recallMessage(msg) }
                                },
                                onCopy: {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                },
                                onImageTap: { url in
                                    fullscreenImageUrl = url
                                    showFullscreenImage = true
                                },
                                onVideoTap: { url in
                                    fullscreenVideoUrl = url
                                    showFullscreenVideo = true
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
        Group {
            if useEnhancedInput {
                VStack(spacing: 0) {
                    // 左侧快捷按钮 + 增强输入栏
                    HStack(spacing: 8) {
                        // 表情按钮
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showEmojiPicker.toggle()
                            }
                            isInputFocused = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray6))
                                    .frame(width: 36, height: 36)

                                Image(systemName: "face.smiling")
                                    .font(.system(size: 20))
                                    .foregroundStyle(showEmojiPicker ? .blue : .primary)
                            }
                        }

                        // 加号按钮：展开附件面板（包含图片/视频入口）
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                showAttachmentPanel.toggle()
                            }
                            isInputFocused = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray6))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(showAttachmentPanel ? .blue : .primary)
                            }
                        }
                        .buttonStyle(.plain)

                        // 增强语音输入栏
                        EnhancedVoiceInputBar(
                            text: $inputText,
                            showKeyboard: $showKeyboard,
                            onSendText: {
                                Task { await send() }
                            },
                            onSendVoice: { url, duration in
                                Task { await sendVoiceMessageEnhanced(url: url, duration: duration) }
                            }
                        )
                        .onChange(of: showKeyboard) { _, newValue in
                            isInputFocused = newValue
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .onChange(of: selectedPhotoItem) { _, newValue in
                        if newValue != nil {
                            Task { await handleMediaSelection() }
                        }
                    }

                    // 附件面板：图片与视频入口
                    if showAttachmentPanel {
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 16))
                                    Text("图片")
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                            }
                            .disabled(isUploadingImage)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                                HStack(spacing: 6) {
                                    Image(systemName: "video")
                                        .font(.system(size: 16))
                                    Text("视频")
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                            }
                            .disabled(isUploadingImage)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // 增强版表情和贴纸选择器（与旧输入栏保持一致）
                    if showEmojiPicker {
                        EnhancedEmojiStickerPicker(
                            onEmojiSelect: { emoji in
                                inputText += emoji
                            },
                            onStickerSelect: { imageURL in
                                Task {
                                    await sendStickerMessage(imageURL: imageURL)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showEmojiPicker = false
                                    }
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            } else {
                legacyInputBarView
            }
        }
    }
    
    private var legacyInputBarView: some View {
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

                // 优化后的输入框
                HStack(spacing: 8) {
                    TextField("发送消息", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .onChange(of: inputText) { _, newValue in
                            handleTyping(newValue)
                        }
                        .font(.body)

                    if !inputText.isEmpty {
                        Button {
                            inputText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 18))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(.systemGray6))

                        // 添加微妙的内阴影效果
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            .padding(0.5)
                    }
                )

                // 右侧圆形按钮组
                HStack(spacing: 8) {
                    // 语音按钮
                    Button {
                        Task {
                            do {
                                let success = try await AudioRecorder.shared.startRecording()
                                if success {
                                    withAnimation(.spring(response: 0.4)) {
                                        showVoiceRecorder = true
                                    }
                                }
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)

                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }

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
                    .transition(AnyTransition.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            // 增强版表情和贴纸选择器
            if showEmojiPicker {
                EnhancedEmojiStickerPicker(
                    onEmojiSelect: { emoji in
                        inputText += emoji
                    },
                    onStickerSelect: { imageURL in
                        Task {
                            await sendStickerMessage(imageURL: imageURL)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showEmojiPicker = false
                            }
                        }
                    }
                )
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
                        sendQuickEmoji(emoji.emoji)
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

            let (mimeType, folder, messageType): (String, String, MessageType)

            if isVideo {
                (mimeType, folder, messageType) = ("video/mp4", "messages/\(myId)/videos", MessageType.video)
            } else {
                (mimeType, folder, messageType) = ("image/jpeg", "messages/\(myId)/images", MessageType.image)
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
                content: mediaUrl,  // 媒体URL作为content
                type: messageType.rawValue
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

    // 发送语音消息
    private func sendVoiceMessage(voiceURL: URL) async {
        guard let myId = authService.currentUser?.id else {
            errorMessage = "请先登录"
            showError = true
            return
        }

        isUploadingVoice = true
        defer { isUploadingVoice = false }

        do {
            // 录音停止后，文件可能尚未完全写入；等待就绪
            let ready = await waitForFileReady(url: voiceURL, timeout: 1.0)
            guard ready else {
                throw NSError(domain: "Voice", code: -100, userInfo: [NSLocalizedDescriptionKey: "录音文件未就绪或不存在"])
            }
            // 读取语音文件数据
            let voiceData = try Data(contentsOf: voiceURL)

            // 上传到服务器
            let uploadedURL = try await supabaseService.uploadVoiceMessage(data: voiceData, userId: myId)

            // 发送消息
            await sendMediaMessage(mediaUrl: uploadedURL, messageType: MessageType.voice)

            // 删除临时文件
            try? FileManager.default.removeItem(at: voiceURL)

            UINotificationFeedbackGenerator().notificationOccurred(.success)

        } catch {
            print("❌ 发送语音消息失败: \(error)")
            errorMessage = "发送语音失败: \(error.localizedDescription)"
            showError = true

            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // 等待本地录音文件准备就绪，避免 stopRecording 后立即读取失败
    private func waitForFileReady(url: URL, timeout: TimeInterval = 1.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? NSNumber,
                   size.intValue > 0 {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        return false
    }

    // 发送贴纸消息
    private func sendStickerMessage(imageURL: String) async {
        await sendMediaMessage(mediaUrl: imageURL, messageType: MessageType.image)
    }

    // MARK: - Data Loading

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let cid = activeConversationId.isEmpty ? conversation.id : activeConversationId
            var fetched = try await supabaseService.fetchMessages(conversationId: cid, limit: 50, offset: 0)
            // 保证时间正序显示
            fetched.sort { $0.createdAt < $1.createdAt }
            messages = fetched

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
            errorHandler.handleDataError(error, operation: "加载对话消息")
            errorMessage = "加载消息失败"
            showError = true
        }
    }

    private func subscribeRealtime() async {
        let cid = activeConversationId.isEmpty ? conversation.id : activeConversationId
        await RealtimeService.shared.subscribeToConversationMessages(conversationId: cid) { msg in
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
                        messages.sort { $0.createdAt < $1.createdAt }
                    }
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
        print("🔍 [DEBUG] send() called")
        
        guard let myId = authService.currentUser?.id else {
            print("❌ [DEBUG] No current user ID")
            errorMessage = "请先登录"
            showError = true
            return
        }
        print("🔍 [DEBUG] Current user ID: \(myId)")

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { 
            print("❌ [DEBUG] Empty text input")
            return 
        }
        print("🔍 [DEBUG] Message text: '\(text)'")

        // 验证对方用户信息
        guard !otherUser.id.isEmpty else {
            print("❌ [DEBUG] Other user ID is empty")
            errorMessage = "无法获取对方信息，请返回重试"
            showError = true
            return
        }
        print("🔍 [DEBUG] Other user ID: \(otherUser.id)")
        print("🔍 [DEBUG] Conversation ID: \(conversation.id)")

        // 添加到待发送列表
        let pendingId = UUID().uuidString
        let pending = PendingMessage(id: pendingId, content: text)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            pendingMessages.append(pending)
        }

        inputText = ""
        isSending = true

        do {
            // 确保使用正确会话ID（若不存在则创建并使用新ID）
            var sendConversationId = activeConversationId.isEmpty ? conversation.id : activeConversationId
            let conversationExists = try await supabaseService.testConversationExists(conversationId: sendConversationId)
            print("🔍 [DEBUG] Conversation exists: \(conversationExists)")

            if !conversationExists {
                print("❌ [DEBUG] Conversation does not exist, trying to create one...")
                let newConversationId = try await supabaseService.getOrCreateConversation(
                    user1Id: myId,
                    user2Id: otherUser.id
                )
                print("🔍 [DEBUG] Created/found conversation: \(newConversationId)")
                sendConversationId = newConversationId
                await MainActor.run {
                    activeConversationId = newConversationId
                }
            }

            // 使用正式发送方法，服务端计算接收者并返回完整消息
            let serverMessage = try await supabaseService.sendMessage(
                conversationId: sendConversationId,
                senderId: myId,
                content: text,
                type: MessageType.text.rawValue
            )

            // 成功反馈
            await MainActor.run {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isSending = false
            }

            // 移除待发送占位并追加服务端消息，避免重复
            withAnimation { pendingMessages.removeAll { $0.id == pendingId } }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(serverMessage)
                messages.sort { $0.createdAt < $1.createdAt }
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
    let onVideoTap: ((String) -> Void)?

    init(message: Message, isMe: Bool, onDelete: (() -> Void)? = nil, onCopy: (() -> Void)? = nil, onImageTap: ((String) -> Void)? = nil, onVideoTap: ((String) -> Void)? = nil) {
        self.message = message
        self.isMe = isMe
        self.onDelete = onDelete
        self.onCopy = onCopy
        self.onImageTap = onImageTap
        self.onVideoTap = onVideoTap
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                // 根据消息类型显示不同内容
                Group {
                    if message.messageType == MessageType.voice {
                        // 语音消息
                        VoiceMessageBubble(
                            voiceURL: message.content,
                            isMe: isMe,
                            duration: message.voiceDuration ?? 0
                        )
                        .shadow(
                            color: isMe ? Color.blue.opacity(0.25) : Color.black.opacity(0.1),
                            radius: 8,
                            x: 0,
                            y: 3
                        )
                    } else if message.messageType == MessageType.video || message.content.isVideoURL {
                        // 视频消息（支持以往将视频标记为 image 的情况）
                        InlineVideoBubblePlayer(urlString: message.content)
                            .frame(maxWidth: 220, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(Rectangle())
                            .onTapGesture { onVideoTap?(message.content) }
                            .shadow(
                                color: isMe ? Color.blue.opacity(0.25) : Color.black.opacity(0.1),
                                radius: 8,
                                x: 0,
                                y: 3
                            )
                    } else if message.messageType == MessageType.image {
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
                    if message.messageType == MessageType.text {
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

                HStack(spacing: 4) {
                    Text(message.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // 已读状态 - 仅在自己发送的消息上显示
                    if isMe {
                        HStack(spacing: 2) {
                            Image(systemName: message.isRead ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(message.isRead ? .blue : .secondary)

                            Text(message.isRead ? "已读" : "未读")
                                .font(.caption2)
                                .foregroundStyle(message.isRead ? .blue : .secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Inline Video Bubble Player (轻量内联播放器 + 失败重试)
private struct InlineVideoBubblePlayer: View {
    let urlString: String
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var item: AVPlayerItem?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if hasError {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "video.badge.exclamationmark")
                                .font(.title2)
                            Text("视频加载失败")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("重试") { setupPlayer() }
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.9))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    )
            } else if isLoading {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("加载中...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanup() }
    }

    private func setupPlayer() {
        isLoading = true
        hasError = false
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        let newItem = AVPlayerItem(url: url)
        item = newItem
        let newPlayer = AVPlayer(playerItem: newItem)
        newItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .readyToPlay:
                    self.player = newPlayer
                    self.isLoading = false
                    newPlayer.play()
                case .failed:
                    self.isLoading = false
                    self.hasError = true
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func cleanup() {
        player?.pause()
        player = nil
        item = nil
        cancellables.removeAll()
    }

    @State private var cancellables = Set<AnyCancellable>()
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

// MARK: - Voice Message Bubble

private struct VoiceMessageBubble: View {
    let voiceURL: String
    let isMe: Bool
    let duration: TimeInterval

    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @State private var isPlaying = false
    @State private var currentPlayer: AVAudioPlayer?
    @State private var resolvedDuration: TimeInterval?

    var body: some View {
        Button {
            Task { await togglePlay() }
        } label: {
            HStack(spacing: 12) {
                // 播放按钮
                ZStack {
                    Circle()
                        .fill(isMe ? Color.white.opacity(0.3) : Color(.systemGray5))
                        .frame(width: 36, height: 36)

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isMe ? .white : .primary)
                }

                // 波形动画
                HStack(spacing: 3) {
                    ForEach(0..<15, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isMe ? Color.white.opacity(0.8) : Color.blue)
                            .frame(width: 3)
                            .frame(height: waveHeight(for: index))
                            .animation(
                                isPlaying ?
                                    .easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.05)
                                    : .default,
                                value: isPlaying
                            )
                    }
                }
                .frame(width: 60, height: 30)

                // 时长
                Text(AudioRecorder.shared.formatTime(resolvedDuration ?? duration))
                    .font(.caption)
                    .foregroundStyle(isMe ? .white.opacity(0.9) : .secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isMe {
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.48, blue: 1.0), Color(red: 0.5, green: 0.4, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .task {
            resolveDurationIfNeeded()
        }
    }

    private func waveHeight(for index: Int) -> CGFloat {
        if isPlaying {
            let baseHeight: CGFloat = 8
            let maxHeight: CGFloat = 28
            // 基于实际音频时长创建动态波形效果
            let effectiveDuration = resolvedDuration ?? duration
            let timeBasedPhase = Date().timeIntervalSinceReferenceDate * (effectiveDuration > 0 ? (2.0 / effectiveDuration) : 1.0)
            let normalizedIndex = CGFloat(index) / 15.0
            let height = baseHeight + (maxHeight - baseHeight) * abs(sin((normalizedIndex + CGFloat(timeBasedPhase)) * .pi))
            return height
        } else {
            // 静态时根据音频时长生成有特色的波形
            let effectiveDuration = resolvedDuration ?? duration
            let normalizedIndex = CGFloat(index) / 15.0
            let durationFactor = min(max(effectiveDuration / 10.0, 0.3), 1.0) // 限制在0.3-1.0之间
            let baseHeight: CGFloat = 8 + 6 * durationFactor
            let maxHeight: CGFloat = 15 + 15 * durationFactor
            let height = baseHeight + (maxHeight - baseHeight) * abs(sin(normalizedIndex * .pi * 2))
            return height
        }
    }

    private func togglePlay() async {
        guard let url = URL(string: voiceURL) else { return }

        if isPlaying {
            audioRecorder.stopPlaying()
            isPlaying = false
        } else {
            do {
                if url.isFileURL {
                    try await audioRecorder.playAudio(url: url)
                } else {
                    try await audioRecorder.playRemoteAudio(url: url)
                }
                isPlaying = true

                // 使用解析出的时长，如果没有则不做延时结束
                let total = resolvedDuration ?? duration
                if total > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + total) {
                        if audioRecorder.isPlaying == false {
                            isPlaying = false
                        }
                    }
                }
            } catch {
                print("❌ 播放语音失败: \(error)")
            }
        }
    }

    // 解析显示时长（兼容远程URL）
    @MainActor
    private func resolveDurationIfNeeded() {
        guard resolvedDuration == nil, let url = URL(string: voiceURL) else { return }
        Task {
            if url.isFileURL {
                resolvedDuration = AudioRecorder.shared.getAudioDuration(url: url)
            } else {
                resolvedDuration = await AudioRecorder.shared.getRemoteAudioDuration(url: url)
            }
        }
    }
}


// MARK: - Enhanced Voice Message Handling Extension

extension ConversationView {
    func sendVoiceMessageEnhanced(url: URL, duration: TimeInterval) async {
        guard let myId = authService.currentUser?.id else {
            errorMessage = "请先登录"
            showError = true
            return
        }
        
        isUploadingVoice = true
        defer { isUploadingVoice = false }
        
        do {
            // 等待文件就绪，避免立即读取失败
            let ready = await waitForFileReady(url: url, timeout: 1.0)
            guard ready else {
                throw NSError(domain: "Voice", code: -100, userInfo: [NSLocalizedDescriptionKey: "录音文件未就绪或不存在"])
            }
            // 读取语音文件数据
            let voiceData = try Data(contentsOf: url)
            
            // 上传到服务器
            let uploadedURL = try await supabaseService.uploadVoiceMessage(data: voiceData, userId: myId)
            
            // 发送语音消息
            _ = try await supabaseService.sendMessage(
                conversationId: conversation.id,
                senderId: myId,
                content: uploadedURL,
                type: MessageType.voice.rawValue
            )
            
            // 添加乐观消息显示
            var optimisticMessage = Message(
                id: "temp-voice-\(UUID().uuidString)",
                conversationId: conversation.id,
                senderId: myId,
                receiverId: otherUser.id,
                sender: authService.currentUser,
                content: uploadedURL,
                messageType: MessageType.voice,
                isRead: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            optimisticMessage.voiceDuration = duration
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    messages.append(optimisticMessage)
                }
            }
            
            // 删除临时文件
            try? FileManager.default.removeItem(at: url)
            
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
        } catch {
            print("❌ 发送增强语音消息失败: \(error)")
            errorMessage = "发送语音失败: \(error.localizedDescription)"
            showError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
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
