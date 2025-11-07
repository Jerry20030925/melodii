//
//  InAppNotificationView.swift
//  Melodii
//
//  应用内消息通知浮窗
//  显示新消息通知并支持快速回复
//

import SwiftUI
import Combine

struct InAppNotificationView: View {
    let message: Message
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var offset: CGFloat = -200
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            // 发送者头像
            if let avatarURL = message.sender?.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    default:
                        Circle()
                            .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(message.sender?.initials ?? "?")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            )
                    }
                }
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(message.sender?.initials ?? "?")
                            .font(.headline)
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.sender?.nickname ?? "用户")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(messagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal)
        .offset(y: offset + dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // 只允许向上拖动
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -50 {
                        // 向上滑动超过50px则关闭
                        dismiss()
                    } else {
                        // 否则回弹
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture {
            onTap()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                offset = 0
            }

            // 5秒后自动消失
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
            }
        }
    }

    private var messagePreview: String {
        switch message.messageType {
        case .text:
            return message.content
        case .image:
            return "[图片]"
        case .video:
            return "[视频]"
        case .voice:
            return "[语音消息]"
        case .system:
            return message.content
        case .sticker:
            return "[贴纸]"
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            offset = -200
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }
}

// MARK: - 通知管理器

@MainActor
class InAppNotificationManager: ObservableObject {
    static let shared = InAppNotificationManager()

    @Published var currentNotification: Message?
    @Published var isPresented = false

    private init() {}

    func show(message: Message) {
        // 如果已经有通知在显示，先关闭
        if isPresented {
            isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.currentNotification = message
                self.isPresented = true
            }
        } else {
            currentNotification = message
            isPresented = true
        }

        // 触觉反馈
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func dismiss() {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentNotification = nil
        }
    }
}

// MARK: - 通知容器视图 (添加到主视图中)

struct InAppNotificationContainer<Content: View>: View {
    @StateObject private var notificationManager = InAppNotificationManager.shared
    @ObservedObject private var authService = AuthService.shared
    let content: Content

    @State private var navigateToConversation: Conversation?

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if notificationManager.isPresented, let message = notificationManager.currentNotification {
                VStack {
                    InAppNotificationView(
                        message: message,
                        onTap: {
                            // 点击通知跳转到对话
                            notificationManager.dismiss()
                            // TODO: 导航到对应的对话页面
                            print("跳转到对话: \(message.conversationId)")
                        },
                        onDismiss: {
                            notificationManager.dismiss()
                        }
                    )
                    .padding(.top, 8)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
    }
}

#Preview {
    InAppNotificationContainer {
        Text("主界面内容")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }
    .onAppear {
        // 模拟通知
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let testMessage = Message(
                id: "test",
                conversationId: "conv1",
                senderId: "user1",
                receiverId: "user2",
                sender: User(id: "user1", nickname: "测试用户"),
                content: "你好，这是一条测试消息！",
                messageType: .text,
                isRead: false,
                createdAt: Date(),
                updatedAt: Date()
            )
            InAppNotificationManager.shared.show(message: testMessage)
        }
    }
}
