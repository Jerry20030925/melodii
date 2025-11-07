//
//  PushNotificationManager.swift
//  Melodii
//
//  iOS系统推送通知管理器
//

import Foundation
import UserNotifications
import UIKit
import SwiftUI
import Combine

@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    // 通知权限状态
    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    // 当前活跃会话（用于过滤通知）
    private var activeConversationId: String?
    
    // 应用状态
    private var isAppInForeground = true
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationObservers()
        checkAuthorizationStatus()
    }
    
    // MARK: - 权限管理
    
    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = granted ? .authorized : .denied
            }
            
            if granted {
                await registerForRemoteNotifications()
            }
            
            return granted
        } catch {
            print("❌ 通知权限请求失败: \(error)")
            await MainActor.run {
                self.isAuthorized = false
                self.authorizationStatus = .denied
            }
            return false
        }
    }
    
    /// 检查当前权限状态
    func checkAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.authorizationStatus = settings.authorizationStatus
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    /// 注册远程推送
    private func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
    }
    
    // MARK: - 活跃会话管理
    
    /// 设置当前活跃会话（防止重复通知）
    func setActiveConversation(_ conversationId: String?) {
        self.activeConversationId = conversationId
        print("📱 设置活跃对话: \(conversationId ?? "nil")")
    }
    
    /// 清除活跃会话
    func clearActiveConversation() {
        self.activeConversationId = nil
        print("📱 清除活跃对话")
    }
    
    // MARK: - 应用状态监听
    
    private func setupNotificationObservers() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        isAppInForeground = true
        print("📱 应用进入前台")
        // 清除应用图标角标
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    @objc private func appWillResignActive() {
        isAppInForeground = false
        print("📱 应用进入后台")
    }
    
    // MARK: - 消息通知
    
    /// 处理新消息通知
    func handleNewMessage(_ message: Message, from sender: User) async {
        print("📱 收到新消息: \(sender.nickname) - \(getNotificationBody(for: message))")
        
        // 检查是否需要发送通知
        guard shouldSendNotification(for: message) else {
            return
        }
        
        await sendLocalNotification(for: message, sender: sender)
    }
    
    /// 判断是否应该发送通知
    private func shouldSendNotification(for message: Message) -> Bool {
        // 如果是自己发的消息，不通知
        if message.senderId == AuthService.shared.currentUser?.id {
            print("📱 跳过通知: 自己发送的消息")
            return false
        }
        
        // 如果没有通知权限，不通知
        guard isAuthorized else {
            print("📱 跳过通知: 无通知权限")
            return false
        }
        
        // 只有当用户正在查看对应的会话页面时才跳过通知
        if let activeConversationId = activeConversationId,
           activeConversationId == message.conversationId {
            print("📱 跳过通知: 用户正在查看此对话")
            return false
        }
        
        print("📱 发送通知: 应用状态=\(isAppInForeground ? "前台" : "后台"), 活跃对话=\(activeConversationId ?? "无")")
        return true
    }
    
    /// 发送本地通知
    private func sendLocalNotification(for message: Message, sender: User) async {
        let content = UNMutableNotificationContent()
        
        // 设置通知内容
        content.title = sender.nickname
        content.body = getNotificationBody(for: message)
        content.sound = UNNotificationSound.default
        
        // 设置通知数据（用于跳转）
        content.userInfo = [
            "type": "message",
            "conversationId": message.conversationId,
            "senderId": message.senderId,
            "messageId": message.id
        ]
        
        // 设置通知标识符
        let identifier = "message_\(message.id)"
        
        // 创建通知请求
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // 立即触发
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ iOS系统推送通知已发送")
            print("   📝 发送者: \(content.title)")
            print("   💬 内容: \(content.body)")
            print("   🆔 消息ID: \(message.id)")
            print("   💬 对话ID: \(message.conversationId)")
            
            // 更新应用角标
            await updateBadgeCount()
            
            // 触觉反馈
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            
        } catch {
            print("❌ 发送iOS系统推送通知失败: \(error)")
        }
    }
    
    /// 获取通知正文内容
    private func getNotificationBody(for message: Message) -> String {
        switch message.messageType {
        case .text:
            return message.content
        case .image:
            return "[图片]"
        case .voice:
            return "[语音消息]"
        case .system:
            return message.content
        case .video:
            return "[视频]"
        case .sticker:
            return "[贴纸]"
        }
    }
    
    /// 更新应用角标数量
    private func updateBadgeCount() async {
        do {
            // 获取未读消息数
            let unreadCount = try await getUnreadMessageCount()
            
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = unreadCount
            }
        } catch {
            print("❌ 更新角标失败: \(error)")
        }
    }
    
    /// 获取未读消息数
    private func getUnreadMessageCount() async throws -> Int {
        guard let userId = AuthService.shared.currentUser?.id else { return 0 }
        return try await SupabaseService.shared.getUnreadMessageCount(userId: userId)
    }
    
    // MARK: - 通知清理
    
    /// 清除特定会话的通知
    func clearNotifications(for conversationId: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let pendingRequests = await center.pendingNotificationRequests()
            let deliveredNotifications = await center.deliveredNotifications()
            
            // 找到需要清除的通知
            let idsToRemove = pendingRequests.compactMap { request in
                if let userInfo = request.content.userInfo as? [String: Any],
                   userInfo["conversationId"] as? String == conversationId {
                    return request.identifier
                }
                return nil
            } + deliveredNotifications.compactMap { notification in
                if let userInfo = notification.request.content.userInfo as? [String: Any],
                   userInfo["conversationId"] as? String == conversationId {
                    return notification.request.identifier
                }
                return nil
            }
            
            if !idsToRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
                center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
                print("🧹 清除了 \(idsToRemove.count) 个通知")
            }
        }
    }
    
    /// 清除所有通知
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
        print("🧹 清除了所有通知")
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    
    /// 应用在前台时收到通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // 检查是否是当前活跃会话的消息
        if let conversationId = userInfo["conversationId"] as? String,
           conversationId == activeConversationId {
            // 当前在对话页面，不显示通知
            completionHandler([])
        } else {
            // 显示通知（横幅和声音）
            completionHandler([.banner, .sound])
        }
    }
    
    /// 用户点击通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // 处理通知点击
        if let type = userInfo["type"] as? String,
           type == "message",
           let conversationId = userInfo["conversationId"] as? String {
            
            // 延迟一点点，确保应用完全启动
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Foundation.NotificationCenter.default.post(
                    name: .openConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
                print("📱 通过通知打开对话: \(conversationId)")
            }
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Foundation.Notification.Name {
    static let openConversation = Foundation.Notification.Name("openConversation")
}

// MARK: - AppDelegate Integration Helper

class AppDelegateHelper: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 初始化推送管理器
        _ = PushNotificationManager.shared
        
        // 如果应用是通过通知启动的
        if let notificationInfo = launchOptions?[.remoteNotification] as? [String: AnyObject] {
            // 延迟处理，确保应用完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // 处理启动通知
                print("📱 应用通过通知启动")
            }
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 远程推送Token: \(tokenString)")
        
        // 这里可以将token发送到后端服务器
        Task {
            await saveDeviceToken(tokenString)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ 远程推送注册失败: \(error)")
    }
    
    private func saveDeviceToken(_ token: String) async {
        // 保存设备token到后端
        print("💾 保存设备Token: \(token)")
        // 实际实现中，这里应该调用API保存到后端
    }
}

// MARK: - SwiftUI Integration View

struct NotificationPermissionView: View {
    @ObservedObject private var pushManager = PushNotificationManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Text("开启消息通知")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("及时接收朋友发来的消息，不错过重要对话")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            VStack(spacing: 12) {
                if pushManager.authorizationStatus == .denied {
                    Button("前往设置") {
                        showingSettings = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Text("请在设置中允许通知权限")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if pushManager.authorizationStatus == .notDetermined {
                    Button("允许通知") {
                        Task {
                            await pushManager.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("通知已开启")
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(40)
        .onAppear {
            pushManager.checkAuthorizationStatus()
        }
        .sheet(isPresented: $showingSettings) {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                SafariView(url: settingsUrl)
            }
        }
    }
}

// MARK: - Safari View for Settings
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            UIApplication.shared.open(self.url)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#Preview {
    NotificationPermissionView()
}
