//
//  MusicDiscoveryView.swift
//  Melodii
//
//  音乐发现：音乐推荐、分类浏览、音乐播放器
//

import SwiftUI
import AVFoundation

struct MusicDiscoveryView: View {
    let recommendations: [MusicRecommendation]
    @Binding var currentIndex: Int
    @Binding var isPlaying: Bool
    @Binding var showPlayer: Bool
    
    @State private var selectedCategory: MusicCategory = .trending
    @State private var searchText = ""
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showMusicSelector = false
    
    var body: some View {
        VStack(spacing: 24) {
            // 头部区域
            headerSection
            
            // 分类选择
            categorySection
            
            // 推荐音乐轮播
            featuredMusicSection
            
            // 音乐网格
            musicGridSection
            
            // 流行趋势
            trendingSection
        }
    }
    
    // MARK: - 头部区域
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("音乐发现")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("为你的内容找到完美的配乐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showMusicSelector = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                    Text("选择配乐")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 分类选择
    
    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MusicCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 精选音乐轮播
    
    private var featuredMusicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("本周精选")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20)
                
                Spacer()
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(recommendations.enumerated()), id: \.offset) { index, music in
                        FeaturedMusicCard(
                            music: music,
                            isPlaying: isPlaying && currentIndex == index
                        ) {
                            playMusic(at: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - 音乐网格
    
    private var musicGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(selectedCategory.emoji) \(selectedCategory.rawValue)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("查看全部") {
                    // 展开分类
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(filteredMusic, id: \.id) { music in
                    MusicGridCard(music: music) {
                        if let index = recommendations.firstIndex(where: { $0.id == music.id }) {
                            playMusic(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 流行趋势
    
    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🔥 热门榜单")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("完整榜单") {
                    // 展开榜单
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(Array(popularMusic.enumerated()), id: \.offset) { index, music in
                    TrendingMusicRow(
                        music: music,
                        rank: index + 1,
                        isPlaying: false
                    ) {
                        if let globalIndex = recommendations.firstIndex(where: { $0.id == music.id }) {
                            playMusic(at: globalIndex)
                        }
                    }
                    
                    if index < popularMusic.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 计算属性
    
    private var filteredMusic: [MusicRecommendation] {
        recommendations.filter { $0.category == selectedCategory }
    }
    
    private var popularMusic: [MusicRecommendation] {
        recommendations
            .filter { $0.isPopular }
            .sorted { $0.usageCount > $1.usageCount }
            .prefix(5)
            .map { $0 }
    }
    
    // MARK: - 音乐播放
    
    private func playMusic(at index: Int) {
        guard recommendations.indices.contains(index) else { return }
        
        currentIndex = index
        isPlaying.toggle()
        showPlayer = true
        
        // 这里应该集成实际的音乐播放逻辑
        print("播放音乐: \(recommendations[index].title)")
    }
}

// MARK: - 分类按钮

struct CategoryButton: View {
    let category: MusicCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(category.emoji)
                    .font(.system(size: 16))
                
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(Capsule())
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 精选音乐卡片

struct FeaturedMusicCard: View {
    let music: MusicRecommendation
    let isPlaying: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // 封面图片
                AsyncImage(url: URL(string: music.coverURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    LinearGradient(
                        colors: music.category.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.6))
                    )
                }
                .frame(width: 160, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    // 播放状态覆盖层
                    ZStack {
                        if isPlaying {
                            Color.black.opacity(0.3)
                            
                            VStack(spacing: 8) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                                
                                Text("播放中")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Color.black.opacity(0.1)
                            
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                
                // 音乐信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Text(music.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack {
                        if music.isPopular {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        
                        Text("\(music.usageCount) 次使用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                }
                .padding(.top, 8)
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPlaying ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPlaying)
    }
}

// MARK: - 音乐网格卡片

struct MusicGridCard: View {
    let music: MusicRecommendation
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // 封面
                AsyncImage(url: URL(string: music.coverURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: music.category.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.7))
                        )
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                )
                
                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(music.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 热门榜单行

struct TrendingMusicRow: View {
    let music: MusicRecommendation
    let rank: Int
    let isPlaying: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 排名
                Text("\(rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(rank <= 3 ? .orange : .secondary)
                    .frame(width: 24)
                
                // 封面
                AsyncImage(url: URL(string: music.coverURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(music.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 使用次数
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(music.usageCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("使用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // 播放按钮
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MusicDiscoveryView(
        recommendations: [
            MusicRecommendation(
                title: "Summer Breeze",
                artist: "Chill Master",
                coverURL: "https://example.com/cover1.jpg",
                audioURL: "https://example.com/audio1.mp3",
                category: .chill,
                usageCount: 1250,
                isPopular: true
            )
        ],
        currentIndex: .constant(0),
        isPlaying: .constant(false),
        showPlayer: .constant(false)
    )
}
