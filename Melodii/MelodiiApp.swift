//
//  MelodiiApp.swift
//  Melodii
//
//  Created by Jianwei Chen on 30/10/2025.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct MelodiiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .environment(\.locale, languageManager.currentLocale)
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    // 当选择“跟随系统”时，系统语言变化后强制刷新一次 Locale（切到英文再切回系统）。
                    if languageManager.currentLanguage == .system {
                        languageManager.setLanguage(.english)
                        languageManager.setLanguage(.system)
                    }
                }
        }
        .modelContainer(for: [User.self, Post.self, Comment.self])
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 初始化推送通知管理器
        _ = PushNotificationManager.shared
        
        // 启动性能监控
        Task { @MainActor in
            PerformanceMonitor.shared.startMonitoring()
        }
        
        // 初始化错误处理器
        _ = ErrorHandler.shared
        
        // 如果应用是通过通知启动的
        if let notificationInfo = launchOptions?[.remoteNotification] as? [String: AnyObject] {
            // 延迟处理，确保应用完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("📱 应用通过通知启动")
            }
        }

        return true
    }

    // MARK: - Remote Notifications

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
