//
//  RootView.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import SwiftUI
import Combine

struct RootView: View {
    @StateObject private var authService = AuthService.shared

    @State private var showSplash = true
    @State private var isCheckingAuth = true

    var body: some View {
        ZStack {
            if showSplash {
                // 启动动画
                SplashView {
                    showSplash = false
                }
            } else if isCheckingAuth {
                // 检查认证状态中 - 显示简单的加载指示器
                ZStack {
                    Color.white
                        .ignoresSafeArea()

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.black)
                }
            } else {
                // 根据认证状态显示不同界面
                if authService.isAuthenticated {
                    if let user = authService.currentUser, user.isOnboardingCompleted {
                        // 已登录且完成引导 -> 显示主页
                        ContentView()
                    } else {
                        // 已登录但未完成引导 -> 显示引导流程
                        OnboardingView()
                    }
                } else {
                    // 未登录 -> 显示登录界面
                    LoginView()
                }
            }
        }
        .task {
            // 并行执行：动画和认证检查
            async let authCheck: Void = checkAuthInBackground()
            async let animationDelay: Void = { try? await Task.sleep(for: .seconds(0.5)) }()

            // 等待两者都完成，但最多等待2秒
            let timeout: Task<Void, Never> = Task {
                // Task.sleep(for:) can throw CancellationError when the task is cancelled.
                // 我们有意用 try? 忽略取消错误
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    if isCheckingAuth {
                        print("⚠️ 认证检查超时，直接进入应用")
                        isCheckingAuth = false
                    }
                }
            }

            // 等待动画和认证检查
            await animationDelay
            await authCheck

            // 取消超时任务（非抛出、非异步）
            timeout.cancel()

            // 完成后解除加载状态
            await MainActor.run {
                isCheckingAuth = false
            }
        }
        // 监听认证状态变化，认证完成后立即解除加载
        .onReceive(authService.objectWillChange) { _ in
            if authService.isAuthenticated {
                isCheckingAuth = false
                
                // 启动实时服务连接
                if let userId = authService.currentUser?.id {
                    Task {
                        await RealtimeService.shared.connect(userId: userId)
                        // 同时启动全局消息监听
                        await RealtimeService.shared.subscribeToMessages(userId: userId) { message in
                            print("🔔 收到全局消息: \(message.content)")
                        }
                        print("✅ RealtimeService 已连接，用户ID: \(userId)")
                    }
                }
            } else {
                // 用户登出时断开连接
                Task {
                    await RealtimeService.shared.disconnect()
                    print("🔌 RealtimeService 已断开连接")
                }
            }
        }
    }

    /// 在后台检查认证状态
    private func checkAuthInBackground() async {
        print("🚀 开始后台认证检查")
        await authService.checkSession()
        print("✅ 后台认证检查完成")
    }
}

#Preview {
    RootView()
}
