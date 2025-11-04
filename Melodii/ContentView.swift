//
//  ContentView.swift
//  Melodii
//
//  Created by Jianwei Chen on 30/10/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var unreadCenter = UnreadCenter.shared

    @State private var selectedTab = 0
    @State private var tabScale: CGFloat = 1.0
    @State private var showNotificationAlert = false
    @State private var hasCheckedNotifications = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home - 主页
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Create - 发布
            CreateView(draftPost: nil)
                .tabItem {
                    Label("", systemImage: "plus.circle.fill")
                }
                .tag(1)

            // Connect - 找到同类
            ConnectView()
                .tabItem {
                    Label("Connect", systemImage: "sparkles")
                }
                .tag(2)

            // Me - 我的
            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person.circle.fill")
                }
                .tag(3)
        }
        .task {
            await initializeBadges()
            await setupDailyLoginReminder()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await initializeBadges()
                    recordLoginAndUpdateReminder()
                }
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // Tab切换时的触觉反馈
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // 微妙的缩放动画
            withAnimation(.easeOut(duration: 0.1)) {
                tabScale = 0.98
            }
            withAnimation(.easeOut(duration: 0.2).delay(0.1)) {
                tabScale = 1.0
            }
        }
        .onAppear {
            // 延迟2秒检查通知权限
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await checkNotificationPermission()
                }
            }
        }
        .alert("开启通知", isPresented: $showNotificationAlert) {
            Button("稍后") {
                UserDefaults.standard.set(true, forKey: "notification_prompt_shown")
            }
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                UserDefaults.standard.set(true, forKey: "notification_prompt_shown")
            }
        } message: {
            Text("开启推送通知，及时接收新消息、点赞和评论通知")
        }
    }

    private func checkNotificationPermission() async {
        guard !hasCheckedNotifications else { return }
        hasCheckedNotifications = true

        // 如果已经提示过，不再显示
        if UserDefaults.standard.bool(forKey: "notification_prompt_shown") {
            return
        }

        await notificationManager.updateAuthorizationStatus()

        // 如果未授权，显示提示
        if notificationManager.authorizationStatus == .notDetermined {
            await MainActor.run {
                showNotificationAlert = true
            }
        }
    }

    private func initializeBadges() async {
        guard let uid = authService.currentUser?.id else {
            UnreadCenter.shared.reset()
            return
        }

        // 异步更新未读计数，避免阻塞主线程
        Task.detached {
            let notificationCount = (try? await SupabaseService.shared.fetchUnreadNotificationCount(userId: uid)) ?? 0
            let messageCount = (try? await SupabaseService.shared.getUnreadMessageCount(userId: uid)) ?? 0

            await MainActor.run {
                UnreadCenter.shared.unreadNotifications = notificationCount
                UnreadCenter.shared.unreadMessages = messageCount
            }
        }
    }

    /// 设置每日登录提醒
    private func setupDailyLoginReminder() async {
        // 检查用户是否已登录
        guard authService.currentUser != nil else { return }

        // 检查是否启用了通知
        await notificationManager.updateAuthorizationStatus()
        guard notificationManager.authorizationStatus == .authorized else {
            print("⚠️ 通知权限未授权，无法设置每日提醒")
            return
        }

        // 设置每日提醒
        await notificationManager.scheduleDailyLoginReminder()
    }

    /// 记录用户登录并更新提醒
    private func recordLoginAndUpdateReminder() {
        // 记录今天已登录
        notificationManager.recordTodayLogin()

        // 如果今天已登录，可以选择取消今天的提醒（可选）
        // notificationManager.cancelDailyLoginReminder()

        print("✅ 用户今日登录已记录")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, Post.self], inMemory: true)
}
