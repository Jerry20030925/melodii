//
//  MusicSelectionSection.swift
//  Melodii
//
//  音乐选择组件
//

import SwiftUI
import AVFoundation

struct MusicSelectionSection: View {
    @Binding var selectedMusic: MusicRecommendation?
    @Binding var showMusicSelector: Bool
    
    @ObservedObject private var musicPlayer = MusicPlayerManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("配乐选择")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Button("音乐库") {
                    showMusicSelector = true
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
            
            if let music = selectedMusic {
                // 已选择的音乐 - 使用新的播放控制器
                VStack(spacing: 16) {
                    MusicPlaybackControls(music: music, compact: false)
                    
                    // 操作按钮
                    HStack(spacing: 12) {
                        Button("更换") {
                            musicPlayer.stopPlaying()
                            showMusicSelector = true
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button("移除") {
                            musicPlayer.stopPlaying()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedMusic = nil
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                        
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: music.category.gradient.map { $0.opacity(0.4) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                        
                        // 微妙的背景色彩
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: music.category.gradient.map { $0.opacity(0.02) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                )
                .shadow(
                    color: music.category.gradient.first?.opacity(0.15) ?? .clear,
                    radius: 12, x: 0, y: 6
                )
            } else {
                // 推荐音乐网格
                VStack(alignment: .leading, spacing: 12) {
                    Text("推荐配乐")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(MusicRecommendation.trending.prefix(4), id: \.id) { music in
                            MusicRecommendationCard(music: music) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedMusic = music
                                }
                            }
                        }
                    }
                    
                    Button("浏览更多音乐") {
                        showMusicSelector = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .onDisappear {
            // 当页面消失时停止播放
            musicPlayer.stopPlaying()
        }
    }
}

struct MusicRecommendationCard: View {
    let music: MusicRecommendation
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // 音乐封面
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
                            VStack(spacing: 4) {
                                Text(music.category.emoji)
                                    .font(.title3)
                                
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        )
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(spacing: 2) {
                    Text(music.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    
                    Text(music.artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if music.isPopular {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("热门")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}


#Preview {
    MusicSelectionSection(
        selectedMusic: .constant(nil),
        showMusicSelector: .constant(false)
    )
}