//
//  MusicPlayerManager.swift
//  Melodii
//
//  音乐播放器管理器 - 处理背景音乐播放
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

@MainActor
class MusicPlayerManager: NSObject, ObservableObject {
    static let shared = MusicPlayerManager()
    
    @Published var isPlaying = false
    @Published var currentMusic: MusicRecommendation?
    @Published var playbackProgress: Double = 0.0
    @Published var playbackDuration: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var currentAudioURL: URL?
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        // deinit is nonisolated; do not call MainActor-isolated APIs here.
        // Perform minimal, thread-safe cleanup without touching @Published or other actor state.
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // MARK: - 音频会话设置
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ 音频会话设置失败: \(error)")
        }
    }
    
    // MARK: - 播放控制
    
    func playMusic(_ music: MusicRecommendation) async {
        currentMusic = music
        
        // 实际应用中应该从真实URL加载音频
        // 现在使用模拟播放
        await simulatePlayback(for: music)
    }
    
    func pauseMusic() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func resumeMusic() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }
    
    func stopPlaying() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentMusic = nil
        playbackProgress = 0.0
        currentTime = 0.0
        stopTimer()
    }
    
    func togglePlayback() {
        if isPlaying {
            pauseMusic()
        } else if audioPlayer != nil {
            resumeMusic()
        }
    }
    
    // MARK: - 进度控制
    
    func seekTo(progress: Double) {
        guard let player = audioPlayer else { return }
        let newTime = progress * playbackDuration
        player.currentTime = newTime
        currentTime = newTime
        playbackProgress = progress
    }
    
    // MARK: - 模拟播放
    
    private func simulatePlayback(for music: MusicRecommendation) async {
        // 停止当前播放
        stopPlaying()
        
        // 模拟音频加载延迟
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        
        // 创建模拟音频播放器（实际应用中应该使用真实音频文件）
        if let url = createSilentAudioFile() {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
                audioPlayer?.numberOfLoops = 0
                
                // 设置播放时长（根据音乐类型模拟不同时长）
                playbackDuration = getSimulatedDuration(for: music)
                audioPlayer?.play()
                
                isPlaying = true
                startTimer()
                
                print("🎵 开始播放: \(music.title) - \(music.artist)")
            } catch {
                print("❌ 创建音频播放器失败: \(error)")
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func getSimulatedDuration(for music: MusicRecommendation) -> TimeInterval {
        // 根据音乐类别模拟不同的播放时长
        switch music.category {
        case .chill, .nature, .study:
            return 180.0 // 3分钟
        case .energetic:
            return 150.0 // 2.5分钟
        case .romantic:
            return 240.0 // 4分钟
        case .trending:
            return 200.0 // 3.33分钟
        }
    }
    
    private func createSilentAudioFile() -> URL? {
        // 创建一个短暂的静音音频文件用于模拟播放
        let audioFilename = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("silent_audio.m4a")
        
        // 如果文件已存在，直接返回
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            return audioFilename
        }
        
        // 创建静音音频文件的简单实现
        // 实际应用中应该有预置的音频文件或网络加载
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let audioFile: AVAudioFile
        
        do {
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: audioFormat.settings)
            
            // 创建3秒的静音数据
            let frameCount = AVAudioFrameCount(audioFormat.sampleRate * 3.0)
            let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
            audioBuffer.frameLength = frameCount
            
            // 写入静音数据
            try audioFile.write(from: audioBuffer)
            
            return audioFilename
        } catch {
            print("❌ 创建静音音频文件失败: \(error)")
            return nil
        }
    }
    
    // MARK: - 定时器
    
    private func startTimer() {
        stopTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }
    
    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer else { return }
        
        currentTime = player.currentTime
        if playbackDuration > 0 {
            playbackProgress = currentTime / playbackDuration
        }
        
        // 检查是否播放完成
        if currentTime >= playbackDuration {
            playbackFinished()
        }
    }
    
    private func playbackFinished() {
        isPlaying = false
        currentTime = 0
        playbackProgress = 0
        stopTimer()
        
        // 可以在这里添加播放完成的回调
        print("🎵 播放完成: \(currentMusic?.title ?? "未知")")
    }
    
    // MARK: - 格式化时间
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate

extension MusicPlayerManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playbackFinished()
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("❌ 音频解码错误: \(error?.localizedDescription ?? "未知错误")")
            stopPlaying()
        }
    }
}

// MARK: - 音乐播放控制视图

struct MusicPlaybackControls: View {
    @ObservedObject private var musicPlayer = MusicPlayerManager.shared
    let music: MusicRecommendation
    let compact: Bool
    
    init(music: MusicRecommendation, compact: Bool = false) {
        self.music = music
        self.compact = compact
    }
    
    var body: some View {
        if compact {
            compactControls
        } else {
            fullControls
        }
    }
    
    // MARK: - 紧凑控制器
    
    private var compactControls: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isCurrentMusicPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .disabled(musicPlayer.currentMusic != nil && musicPlayer.currentMusic?.id != music.id)
            
            if isCurrentMusicPlaying {
                VStack(spacing: 4) {
                    ProgressView(value: musicPlayer.playbackProgress)
                        .frame(width: 60)
                        .tint(.blue)
                    
                    Text(musicPlayer.formatTime(musicPlayer.currentTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
    
    // MARK: - 完整控制器
    
    private var fullControls: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: music.category.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: isCurrentMusicPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Text(music.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isCurrentMusicPlaying {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(musicPlayer.formatTime(musicPlayer.currentTime))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        
                        Text("/ \(musicPlayer.formatTime(musicPlayer.playbackDuration))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            
            if isCurrentMusicPlaying {
                VStack(spacing: 8) {
                    // 进度条
                    ProgressView(value: musicPlayer.playbackProgress)
                        .tint(music.category.gradient.first ?? .blue)
                        .scaleEffect(y: 1.5)
                    
                    // 波形可视化
                    MusicWaveformVisualization(
                        isPlaying: musicPlayer.isPlaying,
                        category: music.category
                    )
                    .frame(height: 30)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: music.category.gradient.map { $0.opacity(0.3) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCurrentMusicPlaying)
    }
    
    // MARK: - 计算属性
    
    private var isCurrentMusicPlaying: Bool {
        musicPlayer.currentMusic?.id == music.id && musicPlayer.isPlaying
    }
    
    // MARK: - 操作
    
    private func togglePlayback() {
        if musicPlayer.currentMusic?.id == music.id {
            musicPlayer.togglePlayback()
        } else {
            Task {
                await musicPlayer.playMusic(music)
            }
        }
        
        // 触觉反馈
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - 音乐波形可视化

struct MusicWaveformVisualization: View {
    let isPlaying: Bool
    let category: MusicCategory
    
    @State private var animationPhase: Double = 0
    
    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<25, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: category.gradient,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 2)
                    .frame(height: waveHeight(for: index))
                    .opacity(isPlaying ? 0.8 : 0.4)
                    .animation(
                        isPlaying ?
                            .easeInOut(duration: Double.random(in: 0.3...0.7))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.03)
                            : .default,
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            if isPlaying {
                animationPhase = 1
            }
        }
        .onChange(of: isPlaying) { _, newValue in
            animationPhase = newValue ? 1 : 0
        }
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        
        if isPlaying {
            let variation = sin(Double(index) * 0.8 + animationPhase * 4) * 0.5 + 0.5
            let randomFactor = sin(Double(index) * 1.2 + animationPhase * 2) * 0.3 + 0.7
            return baseHeight + (maxHeight - baseHeight) * CGFloat(variation * randomFactor)
        } else {
            // 静态波形，基于音乐类别
            let staticVariation = sin(Double(index) * 0.5) * 0.4 + 0.6
            return baseHeight + (maxHeight - baseHeight) * CGFloat(staticVariation) * categoryMultiplier
        }
    }
    
    private var categoryMultiplier: CGFloat {
        switch category {
        case .energetic:
            return 1.0
        case .chill, .nature:
            return 0.6
        case .study:
            return 0.5
        case .romantic:
            return 0.7
        case .trending:
            return 0.9
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        MusicPlaybackControls(
            music: MusicRecommendation(
                title: "夏日微风",
                artist: "轻松音乐团队",
                coverURL: "https://example.com/cover1.jpg",
                audioURL: "https://example.com/audio1.mp3",
                category: .chill,
                usageCount: 1520,
                isPopular: true
            ),
            compact: false
        )
        
        MusicPlaybackControls(
            music: MusicRecommendation(
                title: "活力四射",
                artist: "动感音乐",
                coverURL: "https://example.com/cover6.jpg",
                audioURL: "https://example.com/audio6.mp3",
                category: .energetic,
                usageCount: 1120,
                isPopular: true
            ),
            compact: true
        )
    }
    .padding(20)
}
