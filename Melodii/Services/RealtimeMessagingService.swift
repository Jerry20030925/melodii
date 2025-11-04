//
//  RealtimeMessagingService.swift
//  Melodii
//
//  增强的实时消息服务
//

import Foundation
import Combine
import Supabase
import UIKit

// MARK: - 消息状态枚举

enum MessageStatus: String, Codable {
    case sending = "sending"     // 发送中
    case sent = "sent"          // 已发送
    case delivered = "delivered" // 已送达
    case read = "read"          // 已读
    case failed = "failed"      // 发送失败
}

// MARK: - 增强的消息模型

struct EnhancedMessage: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let receiverId: String
    var sender: User?
    let content: String
    let messageType: MessageType
    var status: MessageStatus
    let isRead: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // 本地状态
    var localId: String? // 用于跟踪本地消息
    var isOptimistic: Bool = false // 是否为乐观更新
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId = "conversation_id"
        case senderId = "sender_id", receiverId = "receiver_id"
        case content, messageType = "message_type"
        case status, isRead = "is_read"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

// MARK: - 实时消息服务

@MainActor
class RealtimeMessagingService: ObservableObject {
    static let shared = RealtimeMessagingService()
    
    private let client = SupabaseConfig.client
    private var subscriptions: Set<AnyCancellable> = []
    private var messageSubscriptions: [String: Task<Void, Never>] = [:]
    
    // 消息缓存和状态管理
    @Published var conversations: [String: [EnhancedMessage]] = [:]
    @Published var messageStatuses: [String: MessageStatus] = [:]
    @Published var typingUsers: [String: Set<String>] = [:] // conversationId -> userIds
    
    // 性能优化
    private let messageQueue = DispatchQueue(label: "com.melodii.messaging", qos: .userInitiated)
    private var pendingMessages: [String: EnhancedMessage] = [:]
    private var statusUpdateTimer: Timer?
    
    private init() {
        setupStatusUpdateTimer()
    }
    
    // MARK: - 订阅管理
    
    func subscribeToConversation(_ conversationId: String) async {
        // 取消之前的订阅
        messageSubscriptions[conversationId]?.cancel()
        
        // 创建新的订阅
        let task = Task { [weak self] in
            guard let self else { return }
            let channel = self.client.realtimeV2.channel("messages:\(conversationId)")
            
            // INSERT 监听
            Task {
                for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "messages") {
                    do {
                        let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                        if message.conversationId == conversationId {
                            await self.handleNewMessage(message)
                        }
                    } catch {
                        print("⚠️ decode message insert failed: \(error)")
                    }
                }
            }
            
            // UPDATE 监听
            Task {
                for await change in channel.postgresChange(UpdateAction.self, schema: "public", table: "messages") {
                    do {
                        let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                        if message.conversationId == conversationId {
                            await self.handleMessageUpdate(message)
                        }
                    } catch {
                        print("⚠️ decode message update failed: \(error)")
                    }
                }
            }
            
            do {
                try await channel.subscribeWithError()
                print("✅ 已订阅会话: \(conversationId)")
            } catch {
                print("❌ 订阅会话失败: \(error)")
            }
        }
        
        messageSubscriptions[conversationId] = task
    }
    
    func unsubscribeFromConversation(_ conversationId: String) {
        messageSubscriptions[conversationId]?.cancel()
        messageSubscriptions.removeValue(forKey: conversationId)
        
        // 清理相关数据
        conversations.removeValue(forKey: conversationId)
        typingUsers.removeValue(forKey: conversationId)
        
        print("🔌 已取消订阅会话: \(conversationId)")
    }
    
    // MARK: - 消息发送（乐观更新）
    
    func sendMessage(
        conversationId: String,
        senderId: String,
        receiverId: String,
        content: String,
        messageType: MessageType
    ) async throws -> EnhancedMessage {
        
        let localId = UUID().uuidString
        let now = Date()
        
        // 创建乐观消息
        let optimisticMessage = EnhancedMessage(
            id: localId,
            conversationId: conversationId,
            senderId: senderId,
            receiverId: receiverId,
            content: content,
            messageType: messageType,
            status: .sending,
            isRead: false,
            createdAt: now,
            updatedAt: now,
            localId: localId,
            isOptimistic: true
        )
        
        // 立即添加到UI（乐观更新）
        await addMessageToConversation(optimisticMessage)
        
        do {
            // 发送到服务器
            let serverMessage = try await SupabaseService.shared.sendMessage(
                conversationId: conversationId,
                senderId: senderId,
                receiverId: receiverId,
                content: content,
                messageType: messageType
            )
            
            // 转换为增强消息
            let enhancedMessage = EnhancedMessage(
                id: serverMessage.id,
                conversationId: serverMessage.conversationId,
                senderId: serverMessage.senderId,
                receiverId: serverMessage.receiverId,
                sender: serverMessage.sender,
                content: serverMessage.content,
                messageType: serverMessage.messageType,
                status: .sent,
                isRead: serverMessage.isRead,
                createdAt: serverMessage.createdAt,
                updatedAt: serverMessage.updatedAt
            )
            
            // 替换乐观消息
            await replaceOptimisticMessage(localId: localId, with: enhancedMessage)
            
            return enhancedMessage
            
        } catch {
            // 发送失败，更新状态
            await updateMessageStatus(localId: localId, status: .failed)
            throw error
        }
    }
    
    // MARK: - 消息状态更新
    
    func markMessageAsRead(_ messageId: String) async {
        do {
            try await SupabaseService.shared.markMessageAsRead(messageId: messageId)
            await updateMessageStatus(localId: messageId, status: .read)
        } catch {
            print("❌ 标记消息已读失败: \(error)")
        }
    }
    
    func markConversationAsRead(_ conversationId: String) async {
        guard let messages = conversations[conversationId] else { return }
        
        let unreadMessages = messages.filter { !$0.isRead && $0.senderId != AuthService.shared.currentUser?.id }
        
        for message in unreadMessages {
            await markMessageAsRead(message.id)
        }
    }
    
    // MARK: - 输入状态
    
    func startTyping(conversationId: String, userId: String) {
        var users = typingUsers[conversationId] ?? Set<String>()
        users.insert(userId)
        typingUsers[conversationId] = users
        
        // 3秒后自动停止
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.stopTyping(conversationId: conversationId, userId: userId)
        }
    }
    
    func stopTyping(conversationId: String, userId: String) {
        var users = typingUsers[conversationId] ?? Set<String>()
        users.remove(userId)
        
        if users.isEmpty {
            typingUsers.removeValue(forKey: conversationId)
        } else {
            typingUsers[conversationId] = users
        }
    }
    
    // MARK: - 私有方法
    
    private func handleNewMessage(_ message: Message) async {
        // 将 Message 转为 EnhancedMessage 并添加
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
        await addMessageToConversation(enhanced)

        // 如果消息不是当前用户发送的，并且应用在后台，发送通知
        let currentUserId = AuthService.shared.currentUser?.id
        if message.senderId != currentUserId {
            await sendNotificationIfNeeded(for: message)
        }
    }

    /// 当收到新消息时，如果应用在后台则发送通知
    private func sendNotificationIfNeeded(for message: Message) async {
        // 检查应用是否在后台
        let appState = await UIApplication.shared.applicationState
        guard appState != .active else {
            print("📱 应用在前台，跳过通知")
            return
        }

        // 获取发送者信息
        let senderName = message.sender?.nickname ?? "某人"

        // 根据消息类型生成通知内容
        let notificationBody: String
        switch message.messageType {
        case .text:
            notificationBody = message.content
        case .image:
            notificationBody = "[图片]"
        case .voice:
            notificationBody = "[语音消息]"
        case .system:
            notificationBody = message.content
        }

        // 发送本地通知
        await NotificationManager.shared.sendMessageNotification(
            from: senderName,
            message: notificationBody,
            conversationId: message.conversationId,
            senderId: message.senderId
        )
    }
    
    private func handleMessageUpdate(_ message: Message) async {
        // 根据更新后的记录，更新本地缓存中的消息（例如已读状态等）
        for (conversationId, messages) in conversations {
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                var updated = messages
                var item = updated[idx]
                item.isOptimistic = false
                item.status = message.isRead ? .read : item.status
                item.sender = message.sender
                item.updatedAt = message.updatedAt
                updated[idx] = item
                conversations[conversationId] = updated
                break
            }
        }
    }
    
    private func addMessageToConversation(_ message: EnhancedMessage) async {
        var messages = conversations[message.conversationId] ?? []
        messages.append(message)
        conversations[message.conversationId] = messages
    }
    
    private func replaceOptimisticMessage(localId: String, with serverMessage: EnhancedMessage) async {
        for (conversationId, messages) in conversations {
            if let index = messages.firstIndex(where: { $0.localId == localId }) {
                var updatedMessages = messages
                updatedMessages[index] = serverMessage
                conversations[conversationId] = updatedMessages
                break
            }
        }
    }
    
    private func updateMessageStatus(localId: String, status: MessageStatus) async {
        messageStatuses[localId] = status
        
        // 更新对话中的消息状态
        for (conversationId, messages) in conversations {
            if let index = messages.firstIndex(where: { $0.id == localId || $0.localId == localId }) {
                var updatedMessages = messages
                updatedMessages[index].status = status
                conversations[conversationId] = updatedMessages
                break
            }
        }
    }
    
    private func setupStatusUpdateTimer() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePendingMessageStatuses()
            }
        }
    }
    
    private func updatePendingMessageStatuses() async {
        // 批量更新消息状态，提高性能
        let sendingMessages = messageStatuses.filter { $0.value == .sending }
        
        for (messageId, _) in sendingMessages {
            // 模拟状态更新逻辑
            if Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 5) < 1 {
                await updateMessageStatus(localId: messageId, status: .sent)
            }
        }
    }
    
    deinit {
        statusUpdateTimer?.invalidate()
        messageSubscriptions.values.forEach { $0.cancel() }
    }
}

// MARK: - 性能监控

extension RealtimeMessagingService {
    func getPerformanceMetrics() -> [String: Any] {
        return [
            "activeSubscriptions": messageSubscriptions.count,
            "cachedConversations": conversations.count,
            "pendingMessages": pendingMessages.count,
            "typingUsers": typingUsers.values.reduce(0) { $0 + $1.count }
        ]
    }
}
