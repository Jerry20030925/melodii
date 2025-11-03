//
//  SplashView.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showText = false
    @State private var opacity: Double = 0

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // 白色背景
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 30) {
                // Logo "M" 字母
                Text("M")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .opacity(opacity)

                // App名称
                if showText {
                    Text("Melodii")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.8))
                        .opacity(opacity)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .onAppear {
            // 第一阶段：logo动画
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                opacity = 1
                isAnimating = true
            }

            // 第二阶段：显示文字
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    showText = true
                }
            }

            // 完成后跳转（缩短时间，避免启动过慢）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    SplashView(onComplete: {})
}
