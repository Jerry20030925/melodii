//
//  MusicSelectorSheet.swift
//  Melodii
//
//  音乐选择弹窗
//

import SwiftUI
import AVFoundation

struct MusicSelectorSheet: View {
    @Binding var selectedMusic: MusicRecommendation?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedCategory: MusicCategory = .trending
    @State private var isPlaying = false
    @State private var currentPlayingId: UUID?
    @State private var audioPlayer: AVAudioPlayer?
    
    // 模拟音乐数据
    private let musicLibrary: [MusicRecommendation] = [
        MusicRecommendation(
            title: "夏日微风",
            artist: "轻松音乐团队",
            coverURL: "https://example.com/cover1.jpg",
            audioURL: "https://example.com/audio1.mp3",
            category: .chill,
            usageCount: 1520,
            isPopular: true
        ),
        MusicRecommendation(
            title: "城市夜光",
            artist: "都市节拍",
            coverURL: "https://example.com/cover2.jpg",
            audioURL: "https://example.com/audio2.mp3",
            category: .trending,
            usageCount: 2100,
            isPopular: true
        ),
        MusicRecommendation(
            title: "森林清晨",
            artist: "自然之声",
            coverURL: "https://example.com/cover3.jpg",
            audioURL: "https://example.com/audio3.mp3",
            category: .nature,
            usageCount: 890,
            isPopular: false
        ),
        MusicRecommendation(
            title: "专注时光",
            artist: "学习音乐",
            coverURL: "https://example.com/cover4.jpg",
            audioURL: "https://example.com/audio4.mp3",
            category: .study,
            usageCount: 1340,
            isPopular: true
        ),
        MusicRecommendation(
            title: "浪漫情怀",
            artist: "情歌王子",
            coverURL: "https://example.com/cover5.jpg",
            audioURL: "https://example.com/audio5.mp3",
            category: .romantic,
            usageCount: 760,
            isPopular: false
        ),
        MusicRecommendation(
            title: "活力四射",
            artist: "动感音乐",
            coverURL: "https://example.com/cover6.jpg",
            audioURL: "https://example.com/audio6.mp3",
            category: .energetic,
            usageCount: 1120,
            isPopular: true
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                searchSection
                
                // 分类选择
                categorySection
                
                // 音乐列表
                musicListSection
            }
            .navigationTitle("选择配乐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        stopCurrentMusic()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        stopCurrentMusic()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onDisappear {
            stopCurrentMusic()
        }
    }
    
    // MARK: - 搜索区域
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("搜索音乐或艺术家", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - 分类选择
    
    private var categorySection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MusicCategory.allCases, id: \.self) { category in
                    CategoryMusicButton(
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
        .padding(.bottom, 16)
    }
    
    // MARK: - 音乐列表
    
    private var musicListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredMusic) { music in
                    MusicSelectionRow(
                        music: music,
                        isSelected: selectedMusic?.id == music.id,
                        isPlaying: currentPlayingId == music.id && isPlaying,
                        onSelect: {
                            selectedMusic = music
                        },
                        onPlayPause: {
                            togglePlayMusic(music)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - 计算属性
    
    private var filteredMusic: [MusicRecommendation] {
        let categoryFiltered = musicLibrary.filter { $0.category == selectedCategory }
        
        if searchText.isEmpty {
            return categoryFiltered
        } else {
            return categoryFiltered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - 音乐播放控制
    
    private func togglePlayMusic(_ music: MusicRecommendation) {
        if currentPlayingId == music.id {
            // 暂停当前音乐
            isPlaying = false
            audioPlayer?.pause()
        } else {
            // 播放新音乐
            stopCurrentMusic()
            playMusic(music)
        }
    }
    
    private func playMusic(_ music: MusicRecommendation) {
        // 这里应该实现实际的音乐播放
        // 现在只是模拟
        currentPlayingId = music.id
        isPlaying = true
        
        // 模拟播放结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if currentPlayingId == music.id {
                isPlaying = false
                currentPlayingId = nil
            }
        }
        
        print("播放音乐: \(music.title) - \(music.artist)")
    }
    
    private func stopCurrentMusic() {
        isPlaying = false
        currentPlayingId = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

// MARK: - 分类音乐按钮

struct CategoryMusicButton: View {
    let category: MusicCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(category.emoji)
                    .font(.system(size: 24))
                
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: category.gradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: isSelected ? category.gradient.first?.opacity(0.3) ?? .clear : .clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 音乐选择行

struct MusicSelectionRow: View {
    let music: MusicRecommendation
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onPlayPause: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // 封面
            AsyncImage(url: URL(string: music.coverURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: music.category.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                // 播放状态覆盖层
                ZStack {
                    if isPlaying {
                        Color.black.opacity(0.3)
                        
                        Image(systemName: "pause.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            )
            .onTapGesture {
                onPlayPause()
            }
            
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
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("热门")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Text("\(music.usageCount) 次使用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // 播放按钮
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            
            // 选择按钮
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isSelected ? Color.green.opacity(0.5) : Color(.systemGray5),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .shadow(
            color: isSelected ? Color.green.opacity(0.2) : .clear,
            radius: isSelected ? 8 : 0,
            x: 0,
            y: isSelected ? 4 : 0
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    MusicSelectorSheet(selectedMusic: .constant(nil))
}