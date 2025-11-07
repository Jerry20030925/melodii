//
//  TrendingView.swift
//  Melodii
//
//  热门趋势视图
//

import SwiftUI

struct TrendingView: View {
    let posts: [Post]
    
    @State private var selectedTimeFrame: TrendingTimeFrame = .today
    @State private var selectedCategory: TrendingCategory = .all
    
    var body: some View {
        VStack(spacing: 20) {
            // 时间范围选择
            timeFrameSelector
            
            // 分类选择
            categorySelector
            
            // 热门帖子列表
            if filteredPosts.isEmpty {
                emptyStateView
            } else {
                trendingPostsList
            }
        }
    }
    
    private var timeFrameSelector: some View {
        HStack {
            Text("热门趋势")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.leading, 20)
            
            Spacer()
            
            Picker("时间范围", selection: $selectedTimeFrame) {
                ForEach(TrendingTimeFrame.allCases, id: \.self) { timeFrame in
                    Text(timeFrame.rawValue).tag(timeFrame)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .padding(.trailing, 20)
        }
    }
    
    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TrendingCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text("\(category.emoji) \(category.rawValue)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category 
                                    ? Color.blue 
                                    : Color(.systemGray6)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var trendingPostsList: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(filteredPosts.enumerated()), id: \.element.id) { index, post in
                TrendingPostCard(post: post, rank: index + 1)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame")
                .font(.system(size: 60))
                .foregroundStyle(.orange.opacity(0.6))
            
            Text("暂无热门内容")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("成为第一个创造热门的人")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private var filteredPosts: [Post] {
        // 这里应该根据时间范围和分类过滤
        return posts
    }
}

enum TrendingTimeFrame: String, CaseIterable {
    case today = "今日"
    case week = "本周"
    case month = "本月"
}

enum TrendingCategory: String, CaseIterable {
    case all = "全部"
    case photo = "图片"
    case video = "视频"
    case text = "文字"
    
    var emoji: String {
        switch self {
        case .all: return "🔥"
        case .photo: return "📸"
        case .video: return "🎥"
        case .text: return "📝"
        }
    }
}

struct TrendingPostCard: View {
    let post: Post
    let rank: Int
    
    var body: some View {
        NavigationLink(destination: PostDetailView(post: post)) {
            HStack(spacing: 16) {
                // 排名
                ZStack {
                    Circle()
                        .fill(rankColor)
                        .frame(width: 36, height: 36)
                    
                    Text("\(rank)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                
                // 内容预览
                VStack(alignment: .leading, spacing: 8) {
                    if let text = post.text, !text.isEmpty {
                        Text(text)
                            .font(.body)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }
                    
                    HStack {
                        Text("@\(post.author.nickname)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        Spacer()
                        
                        Label("\(post.likeCount)", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        
                        Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                // 媒体预览
                if let firstMediaURL = post.mediaURLs.first {
                    AsyncImage(url: URL(string: firstMediaURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color(.systemGray6))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
}

#Preview {
    TrendingView(posts: [])
}