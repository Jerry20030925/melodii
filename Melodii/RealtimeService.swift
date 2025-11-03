//
//  RealtimeService.swift
//  Melodii
//
//  Created by Assistant on 31/10/2025.
//

import Foundation
import Supabase

@MainActor
final class RealtimeService: ObservableObject {
    static let shared = RealtimeService()

    private let client = SupabaseConfig.client
    private var notificationChannel: RealtimeChannel?
    private var conversationChannel: RealtimeChannel?
    private var messageChannels: [String: RealtimeChannel] = [:]

    private init() {}

    // MARK: - Lifecycle

    func connect(userId: String) async {
        // Supabase Swift 客户端会在首次使用时自动管理 socket 连接
        // 这里保留占位，便于未来扩展心跳与网络状态监听
        print("🔌 RealtimeService ready for user: \(userId)")
    }

    func disconnect() async {
        await unsubscribeAll()
        print("🔌 RealtimeService disconnected")
    }

    // MARK: - Notifications

    func subscribeToNotifications(
        userId: String,
        onInsert: @escaping (Notification) -> Void
    ) async {
        await unsubscribeNotifications()

        let channel = client.channel("notifications_user_\(userId)")
        // 订阅 notifications 表的 INSERT 事件
        channel.on(
            RealtimeListenEvent.postgresChanges,
            channel: .postgresChanges(
                event: .insert,
                schema: "public",
                table: "notifications",
                filter: "user_id=eq.\(userId)"
            )
        ) { payload in
            do {
                let data = try JSONSerialization.data(withJSONObject: payload.record, options: [])
                let notif = try JSONDecoder().decode(Notification.self, from: data)
                onInsert(notif)
            } catch {
                print("❌ 解析通知失败: \(error)")
            }
        }

        let status = await channel.subscribe()
        print("📡 Notifications subscribe status: \(status)")
        notificationChannel = channel
    }

    func unsubscribeNotifications() async {
        if let channel = notificationChannel {
            await channel.unsubscribe()
        }
        notificationChannel = nil
    }

    // MARK: - Conversations (optional upsert events)

    func subscribeToConversations(
        userId: String,
        onUpsert: @escaping () -> Void
    ) async {
        // 有些场景会监听 conversations 表的更新，这里提供一个轻量回调
        await unsubscribeConversations()

        let channel = client.channel("conversations_user_\(userId)")
        channel.on(
            RealtimeListenEvent.postgresChanges,
            channel: .postgresChanges(
                event: .update,
                schema: "public",
                table: "conversations",
                filter: "participant1_id=eq.\(userId),participant2_id=eq.\(userId)"
            )
        ) { _ in
            onUpsert()
        }

        let status = await channel.subscribe()
        print("📡 Conversations subscribe status: \(status)")
        conversationChannel = channel
    }

    func unsubscribeConversations() async {
        if let channel = conversationChannel {
            await channel.unsubscribe()
        }
        conversationChannel = nil
    }

    // MARK: - Messages

    func subscribeToMessages(
        conversationId: String,
        onInsert: @escaping (Message) -> Void,
        onUpdate: ((Message) -> Void)? = nil
    ) async {
        await unsubscribeMessages(conversationId: conversationId)

        let channel = client.channel("messages_conv_\(conversationId)")

        // INSERT
        channel.on(
            RealtimeListenEvent.postgresChanges,
            channel: .postgresChanges(
                event: .insert,
                schema: "public",
                table: "messages",
                filter: "conversation_id=eq.\(conversationId)"
            )
        ) { payload in
            do {
                let data = try JSONSerialization.data(withJSONObject: payload.record, options: [])
                let message = try JSONDecoder().decode(Message.self, from: data)
                onInsert(message)
            } catch {
                print("❌ 解析消息失败: \(error)")
            }
        }

        // UPDATE（已读等）
        channel.on(
            RealtimeListenEvent.postgresChanges,
            channel: .postgresChanges(
                event: .update,
                schema: "public",
                table: "messages",
                filter: "conversation_id=eq.\(conversationId)"
            )
        ) { payload in
            guard let onUpdate else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: payload.record, options: [])
                let message = try JSONDecoder().decode(Message.self, from: data)
                onUpdate(message)
            } catch {
                print("❌ 解析消息失败: \(error)")
            }
        }

        let status = await channel.subscribe()
        print("📡 Messages subscribe status: \(status) for conv: \(conversationId)")
        messageChannels[conversationId] = channel
    }

    func unsubscribeMessages(conversationId: String) async {
        if let channel = messageChannels[conversationId] {
            await channel.unsubscribe()
        }
        messageChannels.removeValue(forKey: conversationId)
    }

    func unsubscribeAll() async {
        await unsubscribeNotifications()
        await unsubscribeConversations()
        for (convId, channel) in messageChannels {
            print("🧹 Unsub messages for conv: \(convId)")
            await channel.unsubscribe()
        }
        messageChannels.removeAll()
    }
}
