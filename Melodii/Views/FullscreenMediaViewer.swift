//
//  FullscreenMediaViewer.swift
//  Melodii
//
//  全屏媒体预览：支持图片缩放、视频播放，左右滑动切换多媒体
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

struct FullscreenMediaViewer: View {
    let urls: [String]
    @Binding var isPresented: Bool
    @State var index: Int = 0

    // 优化的视频格式检测：根据扩展名识别视频
    private func isVideo(_ url: String) -> Bool {
        let lower = url.lowercased()
        let videoExtensions = [".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp", ".flv", ".wmv"]
        return videoExtensions.contains { lower.hasSuffix($0) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                    Group {
                        if isVideo(url) {
                            VideoPlayerView(urlString: url)
                                .tag(i)
                        } else {
                            ZoomableAsyncImage(urlString: url)
                                .tag(i)
                        }
                    }
                    .ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // 顶部关闭按钮
            VStack {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(8)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 8)
        }
    }
}

// 可缩放图片
private struct ZoomableAsyncImage: View {
    let urlString: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        let newScale = max(1.0, min(scale * delta, 4.0))
                                        scale = newScale
                                        lastScale = value
                                    }
                                    .onEnded { _ in
                                        lastScale = 1.0
                                        if scale <= 1.01 {
                                            withAnimation(.spring()) {
                                                scale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1.0 else { return }
                                        let translation = value.translation
                                        offset = CGSize(width: lastOffset.width + translation.width, height: lastOffset.height + translation.height)
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.white)
                        Text("加载失败")
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

// 优化的视频播放器
private struct VideoPlayerView: View {
    let urlString: String
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var playerItem: AVPlayerItem?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("视频加载失败")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("请检查网络连接或视频链接")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    
                    Button("重试") {
                        setupPlayer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("加载视频中...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        isLoading = true
        hasError = false
        
        // 清理之前的播放器
        cleanupPlayer()
        
        // 创建新的播放器项目
        let item = AVPlayerItem(url: url)
        playerItem = item
        
        // 监听播放器状态
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            // 视频播放结束，可以添加重播逻辑
        }
        
        // 监听播放器错误
        item.publisher(for: \.status)
            .sink { status in
                DispatchQueue.main.async {
                    switch status {
                    case .readyToPlay:
                        isLoading = false
                        hasError = false
                        if player == nil {
                            player = AVPlayer(playerItem: item)
                        }
                    case .failed:
                        isLoading = false
                        hasError = true
                        print("视频播放失败: \(item.error?.localizedDescription ?? "未知错误")")
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func cleanupPlayer() {
        player?.pause()
        player = nil
        playerItem = nil
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}
