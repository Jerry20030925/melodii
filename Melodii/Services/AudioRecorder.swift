//
//  AudioRecorder.swift
//  Melodii
//
//  语音录制和播放管理器
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import UIKit

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private var currentRecordingURL: URL?

    private override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("❌ 音频会话设置失败: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording() async throws -> Bool {
        // 请求录音权限
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            throw AudioRecorderError.permissionDenied
        }

        // 创建临时录音文件
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        currentRecordingURL = fileURL

        // 设置录音参数
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()

            let success = audioRecorder?.record() ?? false
            if success {
                isRecording = true
                recordingTime = 0

                // 开始计时
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.recordingTime = self.audioRecorder?.currentTime ?? 0
                    }
                }

                // 开始监测音量
                levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.audioRecorder?.updateMeters()
                        let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                        // 将分贝转换为0-1的音量级别
                        let normalizedPower = max(0, min(1, (power + 60) / 60))
                        self.audioLevel = normalizedPower
                    }
                }

                return true
            }
            return false
        } catch {
            print("❌ 录音失败: \(error)")
            throw error
        }
    }

    func stopRecording() -> URL? {
        recordingTimer?.invalidate()
        levelTimer?.invalidate()
        recordingTimer = nil
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0

        return currentRecordingURL
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        levelTimer?.invalidate()
        recordingTimer = nil
        levelTimer = nil

        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0

        // 删除录音文件
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
    }

    // MARK: - Playback

    func playAudio(url: URL) async throws {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            let success = audioPlayer?.play() ?? false
            if success {
                isPlaying = true
            }
        } catch {
            print("❌ 播放失败: \(error)")
            throw error
        }
    }

    /// 播放远程音频（HTTP/HTTPS），通过下载数据后播放，兼容 Supabase 公网 URL
    func playRemoteAudio(url: URL) async throws {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            let success = audioPlayer?.play() ?? false
            if success {
                isPlaying = true
            }
        } catch {
            print("❌ 远程播放失败: \(error)")
            throw error
        }
    }

    func stopPlaying() {
        audioPlayer?.stop()
        isPlaying = false
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Utilities

    func getAudioDuration(url: URL) -> TimeInterval? {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            return player.duration
        } catch {
            return nil
        }
    }

    /// 远程音频的时长（HTTP/HTTPS），通过下载数据后解析
    func getRemoteAudioDuration(url: URL) async -> TimeInterval? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let player = try AVAudioPlayer(data: data)
            return player.duration
        } catch {
            print("⚠️ 获取远程音频时长失败: \(error)")
            return nil
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            isRecording = false
            print("❌ 录音编码错误: \(error?.localizedDescription ?? "未知错误")")
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            isPlaying = false
            print("❌ 播放解码错误: \(error?.localizedDescription ?? "未知错误")")
        }
    }
}

// MARK: - Errors

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case recordingFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要麦克风权限才能录音"
        case .recordingFailed:
            return "录音失败"
        case .playbackFailed:
            return "播放失败"
        }
    }
}
