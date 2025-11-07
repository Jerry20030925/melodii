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
    private var messageSubscriptions: [String: Task<Void, Error>] = [:]
    
    // 消息缓存和状态管理（添加大小限制防止内存泄漏）
    @Published var conversations: [String: [EnhancedMessage]] = [:]
    @Published var messageStatuses: [String: MessageStatus] = [:]
    @Published var typingUsers: [String: Set<String>] = [:] // conversationId -> userIds
    
    // 缓存限制配置
    private let maxMessagesPerConversation = 100
    private let maxCachedConversations = 10
    private let maxMessageStatuses = 1000
    
    // 当前激活的对话（用于避免重复通知）
    @Published var activeConversationId: String?
    
    // 性能优化
    private let messageQueue = DispatchQueue(label: "com.melodii.messaging", qos: .userInitiated)
    private var pendingMessages: [String: EnhancedMessage] = [:]
    private var statusUpdateTimer: Timer?
    
    private init() {
        setupStatusUpdateTimer()
    }
    
    // MARK: - 活跃对话管理
    
    func setActiveConversation(_ conversationId: String?) {
        activeConversationId = conversationId
        PushNotificationManager.shared.setActiveConversation(conversationId)
        print("📱 设置活跃对话: \(conversationId ?? "nil")")
    }
    
    func clearActiveConversation() {
        activeConversationId = nil
        PushNotificationManager.shared.clearActiveConversation()
        print("📱 清除活跃对话")
    }
    
    private func isInActiveConversation(_ conversationId: String) -> Bool {
        return activeConversationId == conversationId
    }
    
    // MARK: - 订阅管理
    
    func subscribeToConversation(_ conversationId: String) async {
        // 取消之前的订阅
        messageSubscriptions[conversationId]?.cancel()
        
        // 创建新的订阅
        let task = Task { [weak self] in
            guard let self else { 
                print("⚠️ RealtimeMessagingService已释放，取消订阅")
                throw CancellationError()
            }
            
            let channel = self.client.realtimeV2.channel("messages:\(conversationId)")
            
            // 使用TaskGroup管理子任务，确保正确清理
            try await withThrowingTaskGroup(of: Void.self) { group in
                // INSERT 监听
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
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
                    } catch {
                        print("⚠️ message insert subscription failed: \(error)")
                        throw error
                    }
                }
                
                // UPDATE 监听
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
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
                    } catch {
                        print("⚠️ message update subscription failed: \(error)")
                        throw error
                    }
                }
                
                // 订阅频道
                do {
                    try await channel.subscribeWithError()
                    print("✅ 已订阅会话: \(conversationId)")
                } catch {
                    print("❌ 订阅会话失败: \(error)")
                    group.cancelAll()
                    throw error
                }
                
                // 等待所有子任务完成或抛出错误
                try await group.waitForAll()
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
                content: content,
                type: messageType.rawValue
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

    /// 当收到新消息时发送通知（由PushNotificationManager处理条件判断）
    private func sendNotificationIfNeeded(for message: Message) async {
        // 获取发送者信息，如果没有则尝试从数据库获取
        var sender = message.sender
        
        if sender == nil {
            // 尝试从用户服务获取发送者信息
            do {
                sender = try await SupabaseService.shared.fetchUser(id: message.senderId)
                print("📱 获取发送者信息成功: \(sender?.nickname ?? "未知")")
            } catch {
                print("❌ 获取发送者信息失败: \(error)")
                // 创建一个临时用户对象
                sender = User(id: message.senderId, nickname: "某人")
            }
        }
        
        // 发送通知（PushNotificationManager会处理所有条件判断）
        if let validSender = sender {
            await PushNotificationManager.shared.handleNewMessage(message, from: validSender)
            print("📱 已处理新消息通知: \(message.id)")
        } else {
            print("⚠️ 无法获取发送者信息，跳过通知")
        }
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
        
        // 限制每个对话的消息数量，防止内存泄漏
        if messages.count > maxMessagesPerConversation {
            messages = Array(messages.suffix(maxMessagesPerConversation))
        }
        
        conversations[message.conversationId] = messages
        
        // 检查是否需要清理旧对话
        await cleanupOldConversationsIfNeeded()
    }
    
    /// 清理旧对话缓存，防止内存泄漏
    private func cleanupOldConversationsIfNeeded() async {
        guard conversations.count > maxCachedConversations else { return }
        
        // 保留最近使用的对话
        let sortedConversations = conversations.sorted { lhs, rhs in
            let lhsLatestTime = lhs.value.last?.createdAt ?? Date.distantPast
            let rhsLatestTime = rhs.value.last?.createdAt ?? Date.distantPast
            return lhsLatestTime > rhsLatestTime
        }
        
        // 删除最旧的对话
        let conversationsToRemove = sortedConversations.suffix(from: maxCachedConversations)
        for (conversationId, _) in conversationsToRemove {
            conversations.removeValue(forKey: conversationId)
            typingUsers.removeValue(forKey: conversationId)
            print("🧹 清理旧对话缓存: \(conversationId)")
        }
    }
    
    /// 清理消息状态缓存
    private func cleanupMessageStatusesIfNeeded() async {
        guard messageStatuses.count > maxMessageStatuses else { return }
        
        // 删除最旧的状态记录（保留最近的）
        let sortedStatuses = messageStatuses.sorted { $0.key < $1.key }
        let statusesToRemove = sortedStatuses.prefix(messageStatuses.count - maxMessageStatuses)
        
        for (messageId, _) in statusesToRemove {
            messageStatuses.removeValue(forKey: messageId)
        }
        
        print("🧹 清理消息状态缓存，删除 \(statusesToRemove.count) 条记录")
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
        
        // 检查是否需要清理状态缓存
        await cleanupMessageStatusesIfNeeded()
        
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
        statusUpdateTimer?.invalidate()
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
