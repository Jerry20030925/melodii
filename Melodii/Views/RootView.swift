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
            // 在后台并行检查认证状态，不阻塞 UI
            async let authCheck: Void = checkAuthInBackground()

            // 等待启动动画完成（缩短到2秒）
            try? await Task.sleep(for: .seconds(2))

            // 等待认证检查完成
            await authCheck
            isCheckingAuth = false
        }
        // 新增：监听认证状态变化，认证后解除加载状态，解决登录后卡死
        .onReceive(authService.objectWillChange) { _ in
            if authService.isAuthenticated {
                isCheckingAuth = false
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
