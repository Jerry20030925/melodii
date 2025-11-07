//
//  RealtimeService.swift
//  Melodii
//
//  统一的 Realtime 订阅中心：通知、消息、会话内消息
//

import Foundation
import Supabase
import Combine
import UserNotifications

@MainActor
final class RealtimeService: ObservableObject {
    static let shared = RealtimeService()

    // 对外发布的新消息（供视图用 onReceive(realtimeService.$newMessage) 监听）
    @Published var newMessage: Message?

    private let client = SupabaseConfig.client

    private var notificationChannel: RealtimeChannelV2?
    private var messagesChannel: RealtimeChannelV2?
    private var conversationChannels: [String: RealtimeChannelV2] = [:]

    // 会话列表全局订阅通道（用于 Conversations/消息列表页面）
    private var conversationsChannel: RealtimeChannelV2?

    // 当前连接的用户ID（用于管理 connect/disconnect）
    private var currentUserId: String?

    private init() {}

    // MARK: - High-level lifecycle

    /// 统一启动：根据用户ID启动所需的实时订阅
    func connect(userId: String) async {
        currentUserId = userId

        // 会话列表全局监听（用于消息页联动）
        await subscribeToConversations(userId: userId) { _ in
            // 这里无需额外处理，视图会通过 $newMessage 或自身回调更新
        }

        // 如需默认同时启动“全局消息监听”或“通知监听”，可取消注释：
        // await subscribeToMessages(userId: userId) { _ in }
        // await subscribeToNotifications(userId: userId) { _ in }
    }

    /// 统一断开：取消所有实时订阅并清理状态
    func disconnect() async {
        currentUserId = nil
        newMessage = nil

        await unsubscribeConversations()
        await unsubscribeMessages()
        await unsubscribeNotifications()

        // 取消所有会话内通道
        for (id, channel) in conversationChannels {
            await channel.unsubscribe()
            conversationChannels[id] = nil
        }
    }

    // MARK: - Helpers

    func clearNewMessage() {
        newMessage = nil
    }

    // MARK: - Notifications

    func subscribeToNotifications(userId: String, onInsert: @escaping (Notification) -> Void) async {
        // 复用已存在的通道
        if let channel = notificationChannel {
            await channel.unsubscribe()
            notificationChannel = nil
        }

        let channel = client.realtimeV2.channel("notifications:\(userId)")
        notificationChannel = channel

        Task {
            for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "notifications") {
                do {
                    let notif = try change.decodeRecord(as: Notification.self, decoder: JSONDecoder())
                    if notif.userId == userId {
                        onInsert(notif)
                        // 收到新的未读通知时，增加全局未读计数
                        if !notif.isRead {
                            UnreadCenter.shared.incrementNotifications()
                        }
                    }
                } catch {
                    print("⚠️ decode notification insert failed: \(error)")
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("❌ subscribe notifications failed: \(error)")
        }
    }

    func unsubscribeNotifications() async {
        if let channel = notificationChannel {
            await channel.unsubscribe()
            notificationChannel = nil
        }
    }

    // MARK: - Messages (global inbox for a user)

    func subscribeToMessages(userId: String, onInsert: @escaping (Message) -> Void) async {
        if let channel = messagesChannel {
            await channel.unsubscribe()
            messagesChannel = nil
        }

        let channel = client.realtimeV2.channel("messages:\(userId)")
        messagesChannel = channel

        Task {
            for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "messages") {
                do {
                    let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                    // 只处理与当前用户相关（收件人或发件人）
                    if message.receiverId == userId || message.senderId == userId {
                        onInsert(message)

                        // 如果是收到的消息（非自己发送），通过PushNotificationManager处理推送通知
                        if message.receiverId == userId && message.senderId != userId {
                            await self.handleIncomingMessage(message)
                        }
                    }
                } catch {
                    print("⚠️ decode message insert failed: \(error)")
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("❌ subscribe messages failed: \(error)")
        }
    }

    /// 处理收到的消息通知
    private func handleIncomingMessage(_ message: Message) async {
        // 获取发送者信息
        do {
            let sender = try await SupabaseService.shared.fetchUserProfile(id: message.senderId)
            
            // 使用新的PushNotificationManager处理通知
            await PushNotificationManager.shared.handleNewMessage(message, from: sender)
            
            print("✅ 已通过PushNotificationManager处理新消息通知")
        } catch {
            print("❌ 获取发送者信息失败: \(error)")
            
            // 创建临时用户对象作为备选方案
            let fallbackSender = User(id: message.senderId, nickname: "某人")
            await PushNotificationManager.shared.handleNewMessage(message, from: fallbackSender)
        }
    }

    func unsubscribeMessages() async {
        if let channel = messagesChannel {
            await channel.unsubscribe()
            messagesChannel = nil
        }
    }

    // MARK: - Conversation specific (single conversation page)

    func subscribeToConversationMessages(conversationId: String, onInsert: @escaping (Message) -> Void) async {
        if let existing = conversationChannels[conversationId] {
            await existing.unsubscribe()
            conversationChannels[conversationId] = nil
        }

        let channel = client.realtimeV2.channel("conversation:\(conversationId)")
        conversationChannels[conversationId] = channel

        // INSERT: 新消息
        Task {
            for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "messages") {
                do {
                    let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                    if message.conversationId == conversationId {
                        onInsert(message)
                    }
                } catch {
                    print("⚠️ decode conversation message insert failed: \(error)")
                }
            }
        }

        // UPDATE: 消息状态更新（用于已读、编辑等实时同步）
        Task {
            for await change in channel.postgresChange(UpdateAction.self, schema: "public", table: "messages") {
                do {
                    let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                    if message.conversationId == conversationId {
                        onInsert(message)
                    }
                } catch {
                    print("⚠️ decode conversation message update failed: \(error)")
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("❌ subscribe conversation(\(conversationId)) failed: \(error)")
        }
    }

    func unsubscribeConversationMessages(conversationId: String) async {
        if let channel = conversationChannels[conversationId] {
            await channel.unsubscribe()
            conversationChannels[conversationId] = nil
        }
    }

    // MARK: - Conversations list (global, for list screens)

    /// 订阅与用户相关的所有新消息，用于会话列表联动与全局新消息提示
    func subscribeToConversations(userId: String, onChange: @escaping (Message) -> Void) async {
        // 若已有旧通道，先退订
        if let channel = conversationsChannel {
            await channel.unsubscribe()
            conversationsChannel = nil
        }

        let channel = client.realtimeV2.channel("conversations:\(userId)")
        conversationsChannel = channel

        Task {
            for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "messages") {
                do {
                    let message = try change.decodeRecord(as: Message.self, decoder: JSONDecoder())
                    // 仅处理与该用户相关的消息
                    if message.receiverId == userId || message.senderId == userId {
                        // 发布到 @Published，供视图 onReceive(realtimeService.$newMessage) 使用
                        self.newMessage = message
                        // 回调给调用方（例如刷新或本地重排）
                        onChange(message)
                    }
                } catch {
                    print("⚠️ decode conversations message insert failed: \(error)")
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("❌ subscribe conversations failed: \(error)")
        }
    }

    func unsubscribeConversations() async {
        if let channel = conversationsChannel {
            await channel.unsubscribe()
            conversationsChannel = nil
        }
    }
}
