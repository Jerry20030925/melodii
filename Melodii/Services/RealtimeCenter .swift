//
//  RealtimeCenter.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import Supabase
import Combine

@MainActor
class RealtimeCenter: ObservableObject {
    static let shared = RealtimeCenter()
    private let client = SupabaseConfig.client

    // Published properties for real-time updates
    @Published var newMessage: Message?
    @Published var newNotification: Notification?
    @Published var unreadMessageCount: Int = 0
    @Published var unreadNotificationCount: Int = 0

    // Realtime channels
    private var messagesChannel: RealtimeChannelV2?
    private var notificationsChannel: RealtimeChannelV2?
    private var userChannels: [String: RealtimeChannelV2] = [:]

    // In-memory callbacks for user updates
    private var userUpdateHandlers: [String: (User) -> Void] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("🔄 RealtimeCenter initialized")
    }

    // MARK: - Connection Management

    /// 启动实时连接（用户登录后调用）
    func connect(userId: String) async {
        print("🔄 Starting realtime connection for user: \(userId)")

        // 订阅消息
        await subscribeToMessages(userId: userId)

        // 订阅通知
        await subscribeToNotifications(userId: userId)

        // 加载未读计数
        await loadUnreadCounts(userId: userId)
    }

    /// 断开实时连接（用户登出后调用）
    func disconnect() async {
        print("🔄 Disconnecting realtime channels")

        // 取消订阅消息
        await messagesChannel?.unsubscribe()
        messagesChannel = nil

        // 取消订阅通知
        await notificationsChannel?.unsubscribe()
        notificationsChannel = nil

        // 取消所有用户更新订阅
        for (userId, channel) in userChannels {
            print("🔄 Unsubscribe user channel: \(userId)")
            await channel.unsubscribe()
        }
        userChannels.removeAll()
        userUpdateHandlers.removeAll()

        // 重置状态
        newMessage = nil
        newNotification = nil
        unreadMessageCount = 0
        unreadNotificationCount = 0
    }

    // MARK: - Messages Subscription

    /// 订阅新消息
    private func subscribeToMessages(userId: String) async {
        print("📬 Subscribing to messages for user: \(userId)")

        // 创建消息频道
        let channel = client.realtimeV2.channel("messages:\(userId)")

        // 监听数据库变化
        let changes = channel.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: "receiver_id=eq.\(userId)")

        Task {
            for await change in changes {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.handleNewMessage(change.record)
                }
            }
        }

        // 订阅频道
        await channel.subscribe()
        messagesChannel = channel
        print("✅ Successfully subscribed to messages channel")
    }

    /// 处理新消息
    private func handleNewMessage(_ record: [String: AnyJSON]) async {
        print("📨 Received new message")

        do {
            // 将AnyJSON转换为可用格式
            var dict: [String: Any] = [:]
            for (key, value) in record {
                dict[key] = convertAnyJSON(value)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            var message = try JSONDecoder().decode(Message.self, from: jsonData)

            // 加载发送者信息
            if let sender = try? await SupabaseService.shared.fetchUser(id: message.senderId) {
                message.sender = sender
            }

            // 发布新消息
            self.newMessage = message

            // 更新未读计数
            self.unreadMessageCount += 1

            print("✅ New message processed: \(message.id)")
        } catch {
            print("❌ Failed to parse new message: \(error)")
        }
    }

    /// 处理消息更新
    private func handleMessageUpdate(_ record: [String: AnyJSON]) async {
        print("🔄 Message updated")

        // 如果消息被标记为已读，减少未读计数
        if case .bool(let isRead) = record["is_read"], isRead {
            if unreadMessageCount > 0 {
                unreadMessageCount -= 1
            }
        }
    }

    // MARK: - Notifications Subscription

    /// 订阅新通知
    private func subscribeToNotifications(userId: String) async {
        print("🔔 Subscribing to notifications for user: \(userId)")

        // 创建通知频道
        let channel = client.realtimeV2.channel("notifications:\(userId)")

        // 监听数据库变化
        let changes = channel.postgresChange(InsertAction.self, schema: "public", table: "notifications", filter: "user_id=eq.\(userId)")

        Task {
            for await change in changes {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.handleNewNotification(change.record)
                }
            }
        }

        // 订阅频道
        await channel.subscribe()
        notificationsChannel = channel
        print("✅ Successfully subscribed to notifications channel")
    }

    /// 处理新通知
    private func handleNewNotification(_ record: [String: AnyJSON]) async {
        print("🔔 Received new notification")

        do {
            // 将AnyJSON转换为可用格式
            var dict: [String: Any] = [:]
            for (key, value) in record {
                dict[key] = convertAnyJSON(value)
            }

            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let notification = try JSONDecoder().decode(Notification.self, from: jsonData)

            // 发布新通知
            self.newNotification = notification

            // 更新未读计数
            self.unreadNotificationCount += 1

            print("✅ New notification processed: \(notification.id)")
        } catch {
            print("❌ Failed to parse new notification: \(error)")
        }
    }

    /// 处理通知更新
    private func handleNotificationUpdate(_ record: [String: AnyJSON]) async {
        print("🔄 Notification updated")

        // 如果通知被标记为已读，减少未读计数
        if case .bool(let isRead) = record["is_read"], isRead {
            if unreadNotificationCount > 0 {
                unreadNotificationCount -= 1
            }
        }
    }

    // MARK: - User Updates (followers/following/likes and more)

    /// 订阅指定用户的实时更新（用于主页统计信息实时刷新）
    func subscribeToUser(userId: String, onUpdate: @escaping (User) -> Void) async {
        // 如果已存在订阅，先取消以避免重复
        if let existing = userChannels[userId] {
            print("🔁 Resubscribing user updates: \(userId)")
            await existing.unsubscribe()
            userChannels.removeValue(forKey: userId)
        }

        let channel = client.realtimeV2.channel("users:\(userId)")

        // 监听 users 表的更新事件（只过滤该用户）
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "users", filter: "id=eq.\(userId)")

        Task {
            for await change in updates {
                await self.handleUserUpdate(change.record, targetUserId: userId)
            }
        }

        // 订阅频道
        await channel.subscribe()
        userChannels[userId] = channel
        userUpdateHandlers[userId] = onUpdate

        print("✅ Subscribed to user updates: \(userId)")
    }

    /// 取消订阅指定用户的实时更新
    func unsubscribeUser(userId: String) async {
        if let channel = userChannels[userId] {
            await channel.unsubscribe()
            userChannels.removeValue(forKey: userId)
            userUpdateHandlers.removeValue(forKey: userId)
            print("✅ Unsubscribed user updates: \(userId)")
        }
    }

    /// 处理用户记录的更新，解析为 User 并调用回调
    private func handleUserUpdate(_ record: [String: AnyJSON], targetUserId: String) async {
        print("👤 User updated (\(targetUserId))")
        do {
            var dict: [String: Any] = [:]
            for (key, value) in record { dict[key] = convertAnyJSON(value) }
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            let updatedUser = try JSONDecoder().decode(User.self, from: jsonData)

            if let handler = userUpdateHandlers[targetUserId] {
                await MainActor.run {
                    handler(updatedUser)
                }
            }
        } catch {
            print("❌ Failed to parse user update: \(error)")
        }
    }

    // MARK: - Unread Counts

    /// 加载未读计数
    private func loadUnreadCounts(userId: String) async {
        print("📊 Loading unread counts for user: \(userId)")

        // 加载未读消息数
        do {
            let messages: [Message] = try await client
                .from("messages")
                .select()
                .eq("receiver_id", value: userId)
                .eq("is_read", value: false)
                .execute()
                .value

            self.unreadMessageCount = messages.count
            print("📬 Unread messages: \(messages.count)")
        } catch {
            print("❌ Failed to load unread messages count: \(error)")
        }

        // 加载未读通知数
        do {
            let notifications: [Notification] = try await client
                .from("notifications")
                .select()
                .eq("user_id", value: userId)
                .eq("is_read", value: false)
                .execute()
                .value

            self.unreadNotificationCount = notifications.count
            print("🔔 Unread notifications: \(notifications.count)")
        } catch {
            print("❌ Failed to load unread notifications count: \(error)")
        }
    }

    // MARK: - Manual Refresh

    /// 手动刷新未读计数
    func refreshUnreadCounts(userId: String) async {
        await loadUnreadCounts(userId: userId)
    }

    /// 重置新消息标志
    func clearNewMessage() {
        newMessage = nil
    }

    /// 重置新通知标志
    func clearNewNotification() {
        newNotification = nil
    }

    // MARK: - Helper Methods

    /// 将AnyJSON转换为Swift原生类型
    func convertAnyJSON(_ value: AnyJSON) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let bool):
            return bool
        case .integer(let int):
            return int
        case .double(let double):
            return double
        case .string(let string):
            return string
        case .array(let array):
                return array.map { convertAnyJSON($0) }
        case .object(let object):
            var dict: [String: Any] = [:]
            for (key, val) in object {
                dict[key] = convertAnyJSON(val)
            }
            return dict
        }
    }
}
