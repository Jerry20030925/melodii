//
//  ShakeDiscoveryView.swift
//  Melodii
//
//  摇一摇发现 - 独特的随机社交功能
//

import SwiftUI
import CoreMotion
import Supabase
import PostgREST

struct ShakeDiscoveryView: View {
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var authService = AuthService.shared

    @State private var discoveredUser: User?
    @State private var isShaking = false
    @State private var showResult = false
    @State private var motionManager = CMMotionManager()
    @State private var shakeCount = 0
    @State private var animationScale: CGFloat = 1.0
    @State private var rotationDegrees: Double = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 动态渐变背景
            AnimatedGradientBackground()

            VStack(spacing: 30) {
                // 顶部标题
                VStack(spacing: 10) {
                    Text("🎲 摇一摇")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("摇动手机，发现有趣的人")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                Spacer()

                // 中心动画区域
                ZStack {
                    // 外圈光环
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 200 + CGFloat(index * 40), height: 200 + CGFloat(index * 40))
                            .scaleEffect(isShaking ? 1.2 : 0.8)
                            .opacity(isShaking ? 0 : 0.5)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                                value: isShaking
                            )
                    }

                    // 中心图标
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .shadow(color: .purple.opacity(0.5), radius: 20, x: 0, y: 10)

                        Image(systemName: isShaking ? "sparkles" : "wand.and.stars")
                            .font(.system(size: 60, weight: .light))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(rotationDegrees))
                    }
                    .scaleEffect(animationScale)
                }

                Spacer()

                // 提示文字
                VStack(spacing: 12) {
                    if isShaking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.blue)

                            Text("正在寻找...")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    } else {
                        Text("摇动手机开始探索")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("已摇动 \(shakeCount) 次")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showResult) {
            if let user = discoveredUser {
                DiscoveredUserSheet(user: user)
            }
        }
        .onAppear {
            startMotionDetection()
        }
        .onDisappear {
            stopMotionDetection()
        }
    }

    // MARK: - Motion Detection

    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { data, error in
            guard let data = data else { return }

            let acceleration = sqrt(
                pow(data.acceleration.x, 2) +
                pow(data.acceleration.y, 2) +
                pow(data.acceleration.z, 2)
            )

            // 检测到摇动
            if acceleration > 2.0 && !isShaking {
                handleShake()
            }
        }
    }

    private func stopMotionDetection() {
        motionManager.stopAccelerometerUpdates()
    }

    private func handleShake() {
        guard !isShaking else { return }

        isShaking = true
        shakeCount += 1

        // 触觉反馈
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // 动画效果
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            animationScale = 1.2
            rotationDegrees += 360
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) {
            animationScale = 1.0
        }

        // 模拟发现用户
        Task {
            await discoverRandomUser()
        }
    }

    private func discoverRandomUser() async {
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        do {
            // 获取随机推荐用户
            let posts = try await supabaseService.fetchTrendingPosts(limit: 10)
            let users = posts.map { $0.author }.filter { $0.id != authService.currentUser?.id }

            if let randomUser = users.randomElement() {
                discoveredUser = randomUser
                showResult = true

                // 保存摇一摇发现记录
                await saveShakeDiscoveryRecord(discoveredUser: randomUser)

                // 成功反馈
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            print("发现用户失败: \(error)")
        }

        isShaking = false
    }
    
    // MARK: - Data Persistence
    
    private func saveShakeDiscoveryRecord(discoveredUser: User) async {
        guard let currentUserId = authService.currentUser?.id else { return }
        
        do {
            // 创建摇一摇发现记录
            let record = [
                "user_id": currentUserId,
                "discovered_user_id": discoveredUser.id,
                "discovery_type": "shake",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ]
            
            try await supabaseService.client
                .from("user_discoveries")
                .insert(record)
                .execute()
            
            print("✅ 摇一摇发现记录已保存")
        } catch {
            print("❌ 保存摇一摇发现记录失败: \(error)")
        }
    }
}

// MARK: - Animated Gradient Background

private struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.blue.opacity(0.1),
                Color.purple.opacity(0.1),
                Color(.systemBackground)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Discovered User Sheet

private struct DiscoveredUserSheet: View {
    let user: User

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 成功动画
                ZStack {
                    ForEach(0..<6, id: \.self) { index in
                        Image(systemName: "sparkle")
                            .font(.title)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(
                                x: cos(Double(index) * .pi / 3) * 60,
                                y: sin(Double(index) * .pi / 3) * 60
                            )
                            .opacity(0.8)
                    }
                }
                .padding(.top, 40)

                // 用户信息
                VStack(spacing: 16) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(user.initials)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .purple.opacity(0.4), radius: 20, x: 0, y: 10)

                    VStack(spacing: 6) {
                        Text(user.nickname)
                            .font(.title2)
                            .fontWeight(.bold)

                        if let mid = user.mid {
                            Text("MID: \(mid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .padding(.top, 8)
                        }
                    }
                }

                Spacer()

                // 操作按钮
                VStack(spacing: 12) {
                    NavigationLink {
                        UserProfileView(user: user)
                    } label: {
                        Text("查看主页")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("继续摇一摇")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .navigationTitle("发现新朋友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ShakeDiscoveryView()
    }
}
