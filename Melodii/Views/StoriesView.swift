//
//  StoriesView.swift
//  Melodii
//
//  动态故事模式：卡片式展示，支持3D翻转效果
//

import SwiftUI

struct StoriesView: View {
    let stories: [StoryCard]
    @Binding var selectedIndex: Int?
    
    @State private var dragOffset: CGSize = .zero
    @State private var currentIndex = 0
    @State private var cardRotations: [Double] = []
    
    var body: some View {
        VStack(spacing: 24) {
            // 故事标题
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日故事")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(stories.count) 个精选故事等你发现")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("查看全部") {
                    // 跳转到故事列表
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            // 3D卡片轮播
            if !stories.isEmpty {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                            StoryCardView(
                                story: story,
                                isSelected: selectedIndex == index,
                                rotation: cardRotations.indices.contains(index) ? cardRotations[index] : 0
                            ) {
                                selectedIndex = index
                            }
                            .frame(width: geometry.size.width - 60)
                            .offset(x: CGFloat(index - currentIndex) * (geometry.size.width - 40))
                            .scaleEffect(index == currentIndex ? 1.0 : 0.85)
                            .opacity(abs(index - currentIndex) <= 1 ? 1.0 : 0.3)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)
                        }
                    }
                }
                .frame(height: 320)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                            
                            // 实时旋转效果
                            let rotation = Double(dragOffset.width / 10)
                            withAnimation(.interactiveSpring()) {
                                if cardRotations.count != stories.count {
                                    cardRotations = Array(repeating: 0, count: stories.count)
                                }
                                cardRotations[currentIndex] = rotation
                            }
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 100
                            
                            if value.translation.width > threshold && currentIndex > 0 {
                                // 向右滑动 - 上一张
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    currentIndex -= 1
                                }
                            } else if value.translation.width < -threshold && currentIndex < stories.count - 1 {
                                // 向左滑动 - 下一张
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    currentIndex += 1
                                }
                            }
                            
                            // 重置拖拽和旋转
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                dragOffset = .zero
                                if cardRotations.indices.contains(currentIndex) {
                                    cardRotations[currentIndex] = 0
                                }
                            }
                        }
                )
                
                // 页面指示器
                PageIndicatorView(
                    currentIndex: currentIndex,
                    totalCount: stories.count
                )
                .padding(.top, 16)
            } else {
                // 空状态
                EmptyStoriesView()
                    .frame(height: 320)
            }
            
            // 快速操作
            QuickActionsView()
                .padding(.horizontal, 20)
        }
        .onAppear {
            cardRotations = Array(repeating: 0, count: stories.count)
        }
    }
}

// MARK: - 故事卡片

struct StoryCardView: View {
    let story: StoryCard
    let isSelected: Bool
    let rotation: Double
    let action: () -> Void
    
    @State private var isLiked = false
    @State private var showPreview = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // 背景渐变
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(0.1),
                                Color.pink.opacity(0.15),
                                Color.orange.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(spacing: 0) {
                    // 封面区域
                    ZStack {
                        if let coverURL = story.coverURL {
                            AsyncImage(url: URL(string: coverURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                gradientPlaceholder
                            }
                        } else {
                            gradientPlaceholder
                        }
                        
                        // 渐变叠加层
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        // 标题叠加
                        VStack {
                            Spacer()
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(story.title)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    
                                    Text("by \(story.author)")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                
                                Spacer()
                            }
                            .padding(20)
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // 内容预览
                    VStack(alignment: .leading, spacing: 12) {
                        Text(story.preview)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        
                        HStack {
                            // 统计信息
                            Label("\(story.posts.count)", systemImage: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            // 互动按钮
                            HStack(spacing: 16) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        isLiked.toggle()
                                    }
                                } label: {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .foregroundStyle(isLiked ? .red : .secondary)
                                        .scaleEffect(isLiked ? 1.2 : 1.0)
                                }
                                
                                Button {
                                    showPreview = true
                                } label: {
                                    Image(systemName: "play.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .font(.system(size: 18))
                        }
                    }
                    .padding(20)
                }
            }
            .rotation3DEffect(
                .degrees(rotation),
                axis: (x: 0, y: 1, z: 0)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: .black.opacity(isSelected ? 0.2 : 0.1),
                radius: isSelected ? 20 : 10,
                x: 0,
                y: isSelected ? 10 : 5
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPreview) {
            StoryPreviewView(story: story)
        }
    }
    
    private var gradientPlaceholder: some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.3),
                Color.pink.opacity(0.4),
                Color.orange.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "book.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
        )
    }
}

// MARK: - 页面指示器

struct PageIndicatorView: View {
    let currentIndex: Int
    let totalCount: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
            }
        }
    }
}

// MARK: - 空状态

struct EmptyStoriesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("暂无故事")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("成为第一个分享故事的人")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button("创建故事") {
                // 跳转到创作页面
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - 快速操作

struct QuickActionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快速操作")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "创建故事",
                    icon: "plus.circle.fill",
                    color: .blue
                ) {
                    // 创建故事
                }
                
                QuickActionButton(
                    title: "随机发现",
                    icon: "shuffle.circle.fill",
                    color: .purple
                ) {
                    // 随机故事
                }
                
                QuickActionButton(
                    title: "我的收藏",
                    icon: "bookmark.circle.fill",
                    color: .orange
                ) {
                    // 收藏列表
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 故事预览

struct StoryPreviewView: View {
    let story: StoryCard
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 故事详情
                    Text(story.title)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("作者: \(story.author)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(story.createdAt, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Text(story.preview)
                        .font(.body)
                        .lineLimit(nil)
                    
                    // 相关帖子
                    if !story.posts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("相关内容")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ForEach(story.posts) { post in
                                EnhancedPostCardView(post: post, enableImageViewer: false)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("故事详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    StoriesView(
        stories: [
            StoryCard(
                title: "城市夜色",
                author: "摄影师小李",
                preview: "记录都市夜晚的霓虹与静谧，每一个角落都有不同的故事...",
                coverURL: nil,
                musicURL: nil,
                posts: [],
                createdAt: Date()
            )
        ],
        selectedIndex: .constant(nil)
    )
}
