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
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
        }
        .modelContainer(for: [User.self, Post.self, Comment.self])
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 设置通知代理
        UNUserNotificationCenter.current().delegate = self

        // 设置通知类别
        Task { @MainActor in
            NotificationManager.shared.setupNotificationCategories()
            await NotificationManager.shared.updateAuthorizationStatus()
        }

        return true
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.setDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRegistrationError(error)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // 在前台接收通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 在前台显示通知
        completionHandler([.banner, .sound, .badge])
    }

    // 处理通知响应（用户点击通知或执行动作）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await NotificationManager.shared.handleNotificationResponse(response)
            completionHandler()
        }
    }
}
