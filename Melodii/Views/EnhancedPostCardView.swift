//
//  EnhancedPostCardView.swift
//  Melodii
//
//  增强的帖子卡片：支持音乐播放、3D效果、交互动画
//

import SwiftUI
import AVFoundation
import AVKit
import Combine

struct EnhancedPostCardView: View {
    let post: Post
    var enableImageViewer: Bool = true
    
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var musicPlayer = MusicPlayerManager.shared
    
    @State private var isLiked = false
    @State private var likeCount: Int
    @State private var isAnimatingLike = false
    @State private var isTogglingLike = false
    @State private var isCollected = false
    @State private var collectCount: Int = 0
    @State private var isTogglingCollect = false
    
    // 音乐播放状态（本地UI状态，用于卡片上的动画与进度展示）
    @State private var isMusicPlaying = false
    @State private var musicProgress: Double = 0
    @State private var showMusicControls = false
    
    // 3D 和动画效果
    @State private var appeared = false
    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    @State private var glowIntensity: Double = 0
    
    // 全屏媒体预览
    @State private var showMediaViewer = false
    @State private var mediaViewerIndex = 0
    
    init(post: Post, enableImageViewer: Bool = true) {
        self.post = post
        self.enableImageViewer = enableImageViewer
        _likeCount = State(initialValue: post.likeCount)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 作者信息区域
            authorSection
            
            // 音乐播放条（如果有配乐）
            if hasMusic {
                musicPlayerSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 媒体内容区域
            if !post.mediaURLs.isEmpty {
                mediaSection
            }
            
            // 文本内容区域
            if let text = post.text, !text.isEmpty {
                textSection(text)
            }
            
            // 话题标签
            if !post.topics.isEmpty {
                topicsSection
            }
            
            Divider()
                .padding(.horizontal, 16)
            
            // 互动操作栏
            interactionSection
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(
                    color: .black.opacity(appeared ? 0.1 : 0),
                    radius: appeared ? 15 : 0,
                    x: 0,
                    y: appeared ? 6 : 0
                )
                .overlay(
                    // 音乐播放时的光晕效果
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(isMusicPlaying ? glowIntensity : 0),
                                    Color.purple.opacity(isMusicPlaying ? glowIntensity * 0.7 : 0),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .blur(radius: 3)
                )
        )
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0)
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 0, y: 1, z: 0)
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appeared)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: rotationAngle)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .task {
            await loadInteractionStates()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
            
            // 音乐光晕动画
            if hasMusic {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    glowIntensity = 0.3
                }
            }
        }
        .simultaneousGesture(
            // 仅在明显的横向拖拽时才触发卡片“倾斜”，避免影响外层纵向滚动
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    // 横向位移明显大于纵向位移时才响应
                    guard abs(dx) > abs(dy) + 8 else { return }
                    if abs(dx) > 20 {
                        let rotation = Double(dx / 10)
                        rotationAngle = min(max(rotation, -15), 15)
                    }
                    isPressed = true
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        rotationAngle = 0
                        isPressed = false
                    }
                }
        )
        .sheet(isPresented: $showMediaViewer) {
            if enableImageViewer {
                EnhancedMediaViewer(
                    urls: post.mediaURLs,
                    initialIndex: mediaViewerIndex,
                    post: post
                )
            }
        }
    }
    
    // MARK: - 作者信息区域
    
    private var authorSection: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: UserProfileView(user: post.author)) {
                AuthorAvatarView(user: post.author, isAnonymous: post.isAnonymous)
            }
            .buttonStyle(.plain)
            .disabled(post.isAnonymous)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(post.isAnonymous ? "匿名" : post.author.nickname)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    if hasMusic {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            
                            Text("配乐")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                
                HStack(spacing: 6) {
                    if !post.isAnonymous {
                        if let mid = post.author.mid, !mid.isEmpty {
                            Text("@\(mid)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Text(post.createdAt.timeAgoDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let city = post.city, !city.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        Text(city)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                showMusicControls.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        }
        .padding(16)
    }
    
    // MARK: - 音乐播放器区域
    
    private var musicPlayerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 音乐封面
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white)
                            .font(.system(size: 16))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(musicArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 播放控制按钮
                Button {
                    toggleMusicPlayback()
                } label: {
                    Image(systemName: isMusicPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse, value: isMusicPlaying)
                }
                .scaleEffect(isMusicPlaying ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMusicPlaying)
            }
            
            // 音乐进度条（本地UI模拟，用于展示）
            if isMusicPlaying {
                VStack(spacing: 4) {
                    ProgressView(value: musicProgress)
                        .tint(.blue)
                        .scaleEffect(y: 0.5)
                    
                    HStack {
                        Text(formatTime(musicProgress * 180))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("3:00")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isMusicPlaying)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            Rectangle()
                .fill(Color(.systemGray6).opacity(0.5))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color(.systemGray4)),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - 媒体内容区域
    
    private var mediaSection: some View {
        Group {
            let isSingleVideo = (post.mediaURLs.count == 1) && (post.mediaURLs.first?.isVideoURL == true)
            
            if isSingleVideo {
                NavigationLink(destination: PostDetailView(post: post)) {
                    EnhancedMediaGrid(
                        urls: post.mediaURLs,
                        hasMusic: hasMusic,
                        onTap: { index in
                            if enableImageViewer {
                                mediaViewerIndex = index
                                showMediaViewer = true
                            }
                        }
                    )
                    .aspectRatio(4/3, contentMode: .fit)
                }
                .buttonStyle(.plain)
            } else {
                EnhancedMediaGrid(
                    urls: post.mediaURLs,
                    hasMusic: hasMusic,
                    onTap: { index in
                        if enableImageViewer {
                            mediaViewerIndex = index
                            showMediaViewer = true
                        }
                    }
                )
                .aspectRatio(mediaAspectRatio(for: post.mediaURLs.count), contentMode: .fit)
            }
        }
        .clipped()
    }
    
    // MARK: - 文本内容区域
    
    private func textSection(_ text: String) -> some View {
        NavigationLink(destination: PostDetailView(post: post)) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .padding(.horizontal, 16)
                .padding(.top, post.mediaURLs.isEmpty ? 0 : 12)
                .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 话题标签区域
    
    private var topicsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(post.topics, id: \.self) { topic in
                    Button("#\(topic)") {
                        // 跳转到话题页面
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - 交互操作栏
    
    private var interactionSection: some View {
        HStack(spacing: 0) {
            // 点赞按钮
            Button {
                Task { await toggleLike() }
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .red : .primary)
                            .scaleEffect(isAnimatingLike ? 1.3 : 1.0)
                            .symbolEffect(.bounce, value: isLiked)
                        
                        Text("\(likeCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(isLiked ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isTogglingLike)
            
            Color(.systemGray5)
                .frame(width: 1, height: 20)
            
            // 评论按钮
            NavigationLink(destination: PostDetailView(post: post)) {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .foregroundStyle(.primary)
                        
                        Text("\(post.commentCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            Color(.systemGray5)
                .frame(width: 1, height: 20)
            
            // 收藏按钮
            Button {
                Task { await toggleCollect() }
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: isCollected ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isCollected ? .blue : .primary)
                        
                        if collectCount > 0 {
                            Text("\(collectCount)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(isCollected ? .blue : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isTogglingCollect)
            
            Color(.systemGray5)
                .frame(width: 1, height: 20)
            
            // 分享按钮（系统分享面板）
            Button {
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showShare) {
                let text = post.text ?? ""
                let urls = post.mediaURLs.compactMap { URL(string: $0) }
                ShareSheet(activityItems: [text] + urls)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - 计算属性
    
    private var hasMusic: Bool {
        // 这里应该检查post是否有关联的音乐
        // 暂时模拟某些帖子有音乐
        return post.id.hashValue % 3 == 0
    }
    
    private var musicTitle: String {
        // 这里应该从post的音乐数据中获取
        return "Summer Vibes"
    }
    
    private var musicArtist: String {
        return "Chill Beats"
    }
    
    // MARK: - 方法
    
    private func mediaAspectRatio(for count: Int) -> CGFloat {
        switch count {
        case 1: return 4.0/3.0
        case 2: return 1.2
        case 3: return 1.2
        default: return 1.2
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func loadInteractionStates() async {
        guard let userId = authService.currentUser?.id else { return }
        
        do {
            async let likedStatus = supabaseService.hasLikedPost(userId: userId, postId: post.id)
            async let collectedStatus = supabaseService.hasCollectedPost(userId: userId, postId: post.id)
            
            let (liked, collected) = try await (likedStatus, collectedStatus)
            
            await MainActor.run {
                isLiked = liked
                isCollected = collected
            }
        } catch {
            print("加载交互状态失败: \(error)")
        }
    }
    
    private func toggleMusicPlayback() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isMusicPlaying.toggle()
        }
        
        if isMusicPlaying {
            // 开始播放音乐：使用共享的 MusicPlayerManager
            Task { @MainActor in
                let synthesized = MusicRecommendation(
                    title: musicTitle,
                    artist: musicArtist,
                    coverURL: post.mediaURLs.first ?? "https://example.com/cover.jpg",
                    audioURL: "https://example.com/audio.mp3",
                    category: .chill,
                    usageCount: 0,
                    isPopular: false
                )
                await musicPlayer.playMusic(synthesized)
            }
            startMusicProgress()
        } else {
            // 暂停音乐
            musicPlayer.pauseMusic()
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func startMusicProgress() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard isMusicPlaying else {
                timer.invalidate()
                return
            }
            
            musicProgress += 0.1 / 180 // 3分钟的歌曲
            
            if musicProgress >= 1.0 {
                musicProgress = 0
                isMusicPlaying = false
                timer.invalidate()
            }
        }
    }
    
    private func toggleLike() async {
        guard let userId = authService.currentUser?.id else { return }
        
        isTogglingLike = true
        let wasLiked = isLiked
        
        // 乐观更新
        await MainActor.run {
            isLiked.toggle()
            likeCount += isLiked ? 1 : -1
            
            if isLiked {
                isAnimatingLike = true
            }
        }
        
        do {
            if isLiked {
                try await supabaseService.likePost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                try await supabaseService.unlikePost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        } catch {
            // 回滚乐观更新
            await MainActor.run {
                isLiked = wasLiked
                likeCount += wasLiked ? 1 : -1
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            print("点赞操作失败: \(error)")
        }
        
        await MainActor.run {
            if isLiked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAnimatingLike = false
                }
            }
            isTogglingLike = false
        }
    }
    
    private func toggleCollect() async {
        guard let userId = authService.currentUser?.id else { return }
        
        isTogglingCollect = true
        let wasCollected = isCollected
        
        await MainActor.run {
            isCollected.toggle()
            collectCount += isCollected ? 1 : -1
        }
        
        do {
            if isCollected {
                try await supabaseService.collectPost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else {
                try await supabaseService.uncollectPost(userId: userId, postId: post.id)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        } catch {
            await MainActor.run {
                isCollected = wasCollected
                collectCount += wasCollected ? 1 : -1
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            print("收藏操作失败: \(error)")
        }
        
        isTogglingCollect = false
    }
    
    @State private var showShare = false
}

// MARK: - 作者头像视图

struct AuthorAvatarView: View {
    let user: User
    let isAnonymous: Bool
    
    var body: some View {
        Group {
            if isAnonymous {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.gray.opacity(0.6), .gray.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("匿")
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    )
            } else if let avatarURL = user.avatarURL, !avatarURL.isEmpty, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(ProgressView().scaleEffect(0.6))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(user.initials)
                            .font(.headline)
                            .foregroundStyle(Color.white)
                    )
            }
        }
        .shadow(color: .purple.opacity(0.3), radius: 4, x: 0, y: 2)
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
    }
}

// MARK: - 增强媒体网格

struct EnhancedMediaGrid: View {
    let urls: [String]
    let hasMusic: Bool
    let onTap: (Int) -> Void
    
    var body: some View {
        let spacing: CGFloat = 3
        
        Group {
            if urls.count == 1 {
                singleMediaView(urls[0], index: 0)
            } else if urls.count == 2 {
                HStack(spacing: spacing) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                        mediaItem(url, index: idx)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 200)
            } else if urls.count == 3 {
                HStack(spacing: spacing) {
                    mediaItem(urls[0], index: 0)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: spacing) {
                        mediaItem(urls[1], index: 1)
                            .frame(maxHeight: .infinity)
                        mediaItem(urls[2], index: 2)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 280)
            } else {
                let firstFour = Array(urls.prefix(4))
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: spacing),
                    GridItem(.flexible(), spacing: spacing)
                ], spacing: spacing) {
                    ForEach(Array(firstFour.enumerated()), id: \.offset) { index, url in
                        ZStack {
                            mediaItem(url, index: index)
                            if index == 3 && urls.count > 4 {
                                Color.black.opacity(0.35)
                                Text("+\(urls.count - 4)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
        }
        .overlay(
            // 音乐播放视觉效果
            hasMusic ?
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.blue.opacity(0.1),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
            : nil
        )
    }
    
    private func singleMediaView(_ url: String, index: Int) -> some View {
        Group {
            if url.isVideoURL {
                EnhancedVideoView(urlString: url, hasMusic: hasMusic)
                    .aspectRatio(4/3, contentMode: .fill)
                    .onTapGesture { onTap(index) }
            } else {
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .onTapGesture { onTap(index) }
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .overlay(ProgressView())
                }
                .aspectRatio(4/3, contentMode: .fill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func mediaItem(_ url: String, index: Int) -> some View {
        Group {
            if url.isVideoURL {
                EnhancedVideoThumbnail(urlString: url, hasMusic: hasMusic)
                    .onTapGesture { onTap(index) }
            } else {
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .onTapGesture { onTap(index) }
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .overlay(ProgressView())
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 增强视频视图

struct EnhancedVideoView: View {
    let urlString: String
    let hasMusic: Bool
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.isMuted = hasMusic // 如果有配乐就静音视频
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if hasError {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text("视频加载失败")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else if isLoading {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        VStack(spacing: 6) {
                            ProgressView()
                                .tint(.white)
                            Text("加载中...")
                                .font(.caption2)
                                .foregroundStyle(.white)
                        }
                    )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.isMuted = hasMusic
        
        self.player = newPlayer
        isLoading = false
    }
}

// MARK: - 增强视频缩略图

struct EnhancedVideoThumbnail: View {
    let urlString: String
    let hasMusic: Bool
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                
                // 播放按钮
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(8)
                    }
                }
                
                // 音乐指示器
                if hasMusic {
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.caption2)
                                Text("配乐")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Capsule())
                            .padding(8)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }
            } else if hasError {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "video.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("无法加载")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else if isLoading {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        Task {
            do {
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 400, height: 400)
                
                let time = CMTime(seconds: 1, preferredTimescale: 600)
                let cgImage = try await imageGenerator.image(at: time).image
                
                await MainActor.run {
                    thumbnail = UIImage(cgImage: cgImage)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    hasError = true
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            EnhancedPostCardView(
                post: Post(
                    id: "preview",
                    author: User(id: "author1", nickname: "预览用户"),
                    text: "这是一个带有配乐的帖子示例",
                    mediaURLs: ["https://example.com/image.jpg"],
                    topics: ["音乐", "分享"],
                    moodTags: [],
                    city: "上海",
                    isAnonymous: false,
                    likeCount: 42,
                    commentCount: 8,
                    collectCount: 15,
                    status: .published,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        }
        .padding()
    }
}
