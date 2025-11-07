//
//  DiscoverView.swift
//  Melodii
//
//  Enhanced Discover Page with 发现精彩 features
//

import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import Combine

struct DiscoverView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    // 导航状态
    @State private var showShakeDiscovery = false
    @State private var showMoodDiary = false
    @State private var showDailyChallenge = false
    @State private var isShowingSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 动态渐变背景
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color.orange.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 32) {
                        // 头部标题区域
                        headerSection
                        
                        // 功能卡片区域
                        featuresSection
                        
                        // 探索内容区域
                        exploreContentSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showShakeDiscovery) {
                ShakeDiscoveryView()
            }
            .sheet(isPresented: $showMoodDiary) {
                MoodDiaryView()
            }
            .sheet(isPresented: $showDailyChallenge) {
                DailyChallengeView()
            }
            .sheet(isPresented: $isShowingSearch) {
                SearchView()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text("✨")
                            .font(.title)
                        
                        Text("发现精彩")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    Text("探索独特功能，连接有趣的人")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                // 摇一摇功能
                FeatureCard(
                    title: "摇一摇",
                    subtitle: "发现有趣的人",
                    icon: "sparkles",
                    gradient: [.blue, .purple],
                    glowColor: .blue
                ) {
                    showShakeDiscovery = true
                }
                
                // 情绪日记功能
                FeatureCard(
                    title: "情绪日记",
                    subtitle: "记录心情变化",
                    icon: "heart.text.square",
                    gradient: [.pink, .red],
                    glowColor: .pink
                ) {
                    showMoodDiary = true
                }
                
                // 每日挑战功能
                FeatureCard(
                    title: "每日挑战",
                    subtitle: "赢取积分奖励",
                    icon: "trophy",
                    gradient: [.orange, .yellow],
                    glowColor: .orange
                ) {
                    showDailyChallenge = true
                }
            }
        }
    }
    
    // MARK: - Explore Content Section
    
    private var exploreContentSection: some View {
        VStack(spacing: 24) {
            HStack {
                Text("推荐内容")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("查看更多") {
                    // Navigate to enhanced discover view
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            
            // 简化的内容预览
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(0..<4) { index in
                    ContentPreviewCard(index: index)
                }
            }
        }
    }
}

// MARK: - Feature Card Component

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let glowColor: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                // 图标区域
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(
                            color: glowColor.opacity(0.4),
                            radius: isPressed ? 20 : 15,
                            x: 0,
                            y: isPressed ? 8 : 5
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                // 文字区域
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [glowColor.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { isPressing in
            isPressed = isPressing
        } perform: {
            action()
        }
    }
}

// MARK: - Content Preview Card

struct ContentPreviewCard: View {
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("精彩内容 \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("有趣的内容描述...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    DiscoverView()
}