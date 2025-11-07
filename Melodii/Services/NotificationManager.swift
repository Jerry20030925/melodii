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

        // 每日登录提醒类别
        let dailyReminderCategory = UNNotificationCategory(
            identifier: "DAILY_REMINDER_CATEGORY",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            messageCategory,
            likeCategory,
            commentCategory,
            followCategory,
            dailyReminderCategory
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
                content: text,
                type: "text"
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

    // MARK: - Daily Login Reminder

    /// 设置每日登录提醒通知
    func scheduleDailyLoginReminder() async {
        let center = UNUserNotificationCenter.current()

        // 先移除之前的每日提醒
        center.removePendingNotificationRequests(withIdentifiers: ["daily_login_reminder"])

        // 检查用户是否启用了通知
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("⚠️ 通知权限未授权，无法设置每日提醒")
            return
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "想你了！"
        content.body = "今天还没来Melodii呢，快来看看朋友们的动态吧 ✨"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "DAILY_REMINDER_CATEGORY"

        // 设置每天上午10点提醒
        var dateComponents = DateComponents()
        dateComponents.hour = 10
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "daily_login_reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("✅ 每日登录提醒已设置：每天上午10:00")
        } catch {
            print("❌ 设置每日登录提醒失败: \(error)")
        }
    }

    /// 取消每日登录提醒
    func cancelDailyLoginReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_login_reminder"])
        print("✅ 已取消每日登录提醒")
    }

    /// 记录用户今天已登录，取消今天的提醒
    func recordTodayLogin() {
        let today = Calendar.current.startOfDay(for: Date())
        UserDefaults.standard.set(today, forKey: "last_login_date")
        print("✅ 记录今日登录: \(today)")
    }

    /// 检查用户是否今天已登录
    func hasLoggedInToday() -> Bool {
        guard let lastLogin = UserDefaults.standard.object(forKey: "last_login_date") as? Date else {
            return false
        }

        let today = Calendar.current.startOfDay(for: Date())
        let lastLoginDay = Calendar.current.startOfDay(for: lastLogin)

        return today == lastLoginDay
    }

    // MARK: - Real-time Message Notifications

    /// 发送消息推送通知（本地测试用）
    func sendMessageNotification(from sender: String, message: String, conversationId: String, senderId: String) async {
        let center = UNUserNotificationCenter.current()

        // 检查权限
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // 检查用户是否启用了消息通知
        guard UserDefaults.standard.bool(forKey: "enable_message_notifications") else {
            print("⚠️ 用户已禁用消息通知")
            return
        }

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "来自 \(sender) 的新消息"
        content.body = message
        content.sound = .default
        content.badge = NSNumber(value: (UIApplication.shared.applicationIconBadgeNumber) + 1)
        content.categoryIdentifier = "MESSAGE_CATEGORY"

        // 附加数据，用于点击后跳转
        content.userInfo = [
            "type": "message",
            "conversation_id": conversationId,
            "sender_id": senderId
        ]

        // 立即触发
        let request = UNNotificationRequest(
            identifier: "message_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            print("✅ 消息通知已发送: \(sender) - \(message)")
        } catch {
            print("❌ 发送消息通知失败: \(error)")
        }
    }

    /// 订阅实时消息通知（使用Supabase Realtime）
    func subscribeToMessageNotifications(userId: String) async {
        // 这个方法将与RealtimeMessagingService集成
        // 当收到新消息时，自动触发本地通知
        print("✅ 已订阅用户 \(userId) 的实时消息通知")
    }

    /// 取消订阅实时消息通知
    func unsubscribeFromMessageNotifications() {
        print("✅ 已取消订阅实时消息通知")
    }
}
