//
//  NotificationManager.swift
//  Melodii
//
//  Push notification manager for iOS with reply support
//

import Foundation
import UserNotifications
import UIKit
import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var deviceToken: String?
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
    }

    // MARK: - Permission Request

    func requestAuthorization() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]

        do {
            let granted = try await center.requestAuthorization(options: options)
            await updateAuthorizationStatus()

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }

            return granted
        } catch {
            print("❌ 请求通知权限失败: \(error)")
            throw error
        }
    }

    func updateAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Device Token

    func setDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        print("📱 设备令牌: \(token)")

        // 保存到UserDefaults
        UserDefaults.standard.set(token, forKey: "device_token")

        // 上传到服务器
        Task {
            await uploadDeviceToken(token)
        }
    }

    private func uploadDeviceToken(_ token: String) async {
        guard let userId = AuthService.shared.currentUser?.id else { return }

        // TODO: 上传设备令牌到Supabase
        // 需要在SupabaseService中添加updateUserDeviceToken方法
        print("📱 设备令牌待上传: \(token) for user: \(userId)")
    }

    func handleRegistrationError(_ error: Error) {
        print("❌ 注册推送通知失败: \(error)")
    }

    // MARK: - Notification Categories

    func setupNotificationCategories() {
        let center = UNUserNotificationCenter.current()

        // 消息通知类别（带回复动作）
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "回复",
            options: [.authenticationRequired],
            textInputButtonTitle: "发送",
            textInputPlaceholder: "输入回复内容..."
        )

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION",
            title: "标记为已读",
            options: []
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // 点赞通知类别
        let likeCategory = UNNotificationCategory(
            identifier: "LIKE_CATEGORY",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // 评论通知类别
        let commentCategory = UNNotificationCategory(
            identifier: "COMMENT_CATEGORY",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // 关注通知类别
        let followCategory = UNNotificationCategory(
            identifier: "FOLLOW_CATEGORY",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            messageCategory,
            likeCategory,
            commentCategory,
            followCategory
        ])

        print("✅ 通知类别已设置")
    }

    // MARK: - Handle Notification Actions

    func handleNotificationResponse(_ response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        switch actionIdentifier {
        case "REPLY_ACTION":
            if let textResponse = response as? UNTextInputNotificationResponse {
                await handleReplyAction(userInfo: userInfo, text: textResponse.userText)
            }

        case "MARK_READ_ACTION":
            await handleMarkReadAction(userInfo: userInfo)

        case UNNotificationDefaultActionIdentifier:
            // 用户点击了通知本身
            handleNotificationTap(userInfo: userInfo)

        default:
            break
        }
    }

    private func handleReplyAction(userInfo: [AnyHashable: Any], text: String) async {
        guard let conversationId = userInfo["conversation_id"] as? String,
              let senderId = AuthService.shared.currentUser?.id,
              let receiverId = userInfo["sender_id"] as? String else {
            print("❌ 回复消息失败：缺少必要信息")
            return
        }

        do {
            _ = try await SupabaseService.shared.sendMessage(
                conversationId: conversationId,
                senderId: senderId,
                receiverId: receiverId,
                content: text,
                messageType: .text
            )
            print("✅ 快速回复发送成功")

            // 显示成功提示
            await showLocalNotification(title: "回复已发送", body: text)
        } catch {
            print("❌ 快速回复失败: \(error)")
            await showLocalNotification(title: "回复失败", body: "请打开应用重试")
        }
    }

    private func handleMarkReadAction(userInfo: [AnyHashable: Any]) async {
        guard let messageId = userInfo["message_id"] as? String else {
            print("❌ 标记已读失败：缺少消息ID")
            return
        }

        do {
            try await SupabaseService.shared.markMessageAsRead(messageId: messageId)
            print("✅ 消息已标记为已读")
        } catch {
            print("❌ 标记已读失败: \(error)")
        }
    }

    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        // 根据通知类型导航到相应页面
        let notificationType = userInfo["type"] as? String ?? ""

        NotificationCenter.default.post(
            name: NSNotification.Name("OpenNotification"),
            object: nil,
            userInfo: userInfo
        )

        print("📱 用户点击了通知: \(notificationType)")
    }

    // MARK: - Local Notifications

    private func showLocalNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("❌ 显示本地通知失败: \(error)")
        }
    }

    // MARK: - Badge Management

    func updateBadgeCount(_ count: Int) {
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } catch {
                print("❌ 更新badge失败: \(error)")
            }
        }
    }

    func clearBadge() {
        updateBadgeCount(0)
    }
}
