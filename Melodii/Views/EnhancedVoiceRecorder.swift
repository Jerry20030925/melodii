//
//  EnhancedVoiceRecorder.swift
//  Melodii
//
//  增强语音录制器：微信式长按录音 + 键盘动画过渡
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - 增强语音输入组件
struct EnhancedVoiceInputBar: View {
    @Binding var text: String
    @Binding var showKeyboard: Bool
    let onSendText: () -> Void
    let onSendVoice: (URL, TimeInterval) -> Void
    
    // 状态管理
    @State private var inputMode: InputMode = .keyboard
    @State private var isRecording = false
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    
    // 动画状态
    @State private var voiceButtonScale: CGFloat = 1.0
    @State private var recordingOffset: CGSize = .zero
    @State private var isCancelling = false
    @State private var showRecordingTip = false
    
    // 键盘状态
    @FocusState private var isTextFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    
    enum InputMode {
        case keyboard, voice
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 录音提示层
            if showRecordingTip {
                recordingTipView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 主输入区域
            HStack(spacing: 12) {
                // 模式切换按钮
                modeToggleButton
                
                // 输入区域
                inputAreaView
                
                // 发送按钮
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(Color(.systemGray4)),
                alignment: .top
            )
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: inputMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.isEmpty)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showRecordingTip)
        .onChange(of: isTextFieldFocused) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showKeyboard = newValue
                if newValue {
                    inputMode = .keyboard
                }
            }
        }
        .onAppear {
            setupAudioSession()
        }
    }
    
    // MARK: - 模式切换按钮
    
    private var modeToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                if inputMode == .keyboard {
                    // 切换到语音模式
                    inputMode = .voice
                    isTextFieldFocused = false
                    showKeyboard = false
                } else {
                    // 切换到键盘模式
                    inputMode = .keyboard
                    isTextFieldFocused = true
                }
            }
            
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(inputMode == .keyboard ? Color(.systemGray5) : Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(
                                inputMode == .voice ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: inputMode == .keyboard ? "mic.fill" : "keyboard.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(inputMode == .keyboard ? .secondary : Color.blue)
                    .symbolEffect(.bounce, value: inputMode)
            }
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
    
    // MARK: - 输入区域
    
    private var inputAreaView: some View {
        Group {
            if inputMode == .keyboard {
                keyboardInputView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                voiceInputView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
    }
    
    private var keyboardInputView: some View {
        HStack(spacing: 8) {
            TextField("输入消息...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isTextFieldFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isTextFieldFocused ? Color.blue.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
    }
    
    private var voiceInputView: some View {
        Button {
            // 空实现，实际逻辑在手势中
        } label: {
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isRecording ? .red : .blue)
                        .symbolEffect(.pulse, options: .repeating, value: isRecording)
                    
                    Text(isRecording ? recordingText : "按住说话")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isRecording ? .red : .blue)
                        .monospacedDigit()
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isRecording ? Color.red.opacity(0.5) : Color.blue.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(voiceButtonScale)
            .offset(recordingOffset)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isRecording && abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                        // 开始录音
                        startRecording()
                    }
                    
                    if isRecording {
                        recordingOffset = value.translation
                        
                        // 检查是否要取消
                        let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                        let shouldCancel = distance > 100
                        
                        if shouldCancel != isCancelling {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCancelling = shouldCancel
                                voiceButtonScale = shouldCancel ? 0.9 : 1.1
                            }
                            
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .onEnded { value in
                    if isRecording {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            recordingOffset = .zero
                            voiceButtonScale = 1.0
                        }
                        
                        if isCancelling {
                            cancelRecording()
                        } else {
                            stopRecording()
                        }
                        
                        isCancelling = false
                    }
                }
        )
    }
    
    private var recordingText: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - 发送按钮
    
    private var sendButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onSendText()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
    
    // MARK: - 录音提示视图
    
    private var recordingTipView: some View {
        VStack(spacing: 8) {
            if isCancelling {
                Label("松开手指取消录音", systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: isCancelling)
            } else {
                HStack(spacing: 8) {
                    // 录音动画
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(Color.red)
                                .frame(width: 4, height: 4)
                                .opacity(recordingAnimationOpacity(for: index))
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.1),
                                    value: isRecording
                                )
                        }
                    }
                    
                    Text("录音中 \(recordingText)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                    
                    Text("• 向上滑动取消")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private func recordingAnimationOpacity(for index: Int) -> Double {
        if !isRecording { return 0.3 }
        
        let phase = (Date().timeIntervalSince1970 * 2).truncatingRemainder(dividingBy: 2.0)
        let normalizedIndex = Double(index) / 4.0
        
        if abs(phase - normalizedIndex) < 0.2 {
            return 1.0
        } else {
            return 0.3
        }
    }
    
    // MARK: - 录音逻辑
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ 音频会话设置失败: \(error)")
        }
    }
    
    private func startRecording() {
        guard !isRecording else { return }
        
        // 请求麦克风权限
        AVAudioSession.sharedInstance().requestRecordPermission { [self] allowed in
            DispatchQueue.main.async {
                if allowed {
                    performStartRecording()
                } else {
                    // 权限被拒绝，显示提示
                    print("❌ 麦克风权限被拒绝")
                }
            }
        }
    }
    
    private func performStartRecording() {
        do {
            // 创建录音文件
            let fileName = "voice_\(Date().timeIntervalSince1970).m4a"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            recordingURL = documentsPath.appendingPathComponent(fileName)
            
            // 录音设置
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // 创建录音器
            if let url = recordingURL {
                audioRecorder = try AVAudioRecorder(url: url, settings: settings)
                audioRecorder?.delegate = AudioRecorderDelegate()
                audioRecorder?.isMeteringEnabled = true
                audioRecorder?.record()
                
                // 更新状态
                isRecording = true
                recordingStartTime = Date()
                recordingDuration = 0
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showRecordingTip = true
                    voiceButtonScale = 1.1
                }
                
                // 启动计时器
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    if let startTime = recordingStartTime {
                        recordingDuration = Date().timeIntervalSince(startTime)
                        
                        // 自动停止录音（最多60秒）
                        if recordingDuration >= 60 {
                            stopRecording()
                        }
                    }
                }
                
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch {
            print("❌ 录音开始失败: \(error)")
        }
    }
    
    private func stopRecording() {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return }
        
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isRecording = false
            showRecordingTip = false
            voiceButtonScale = 1.0
        }
        
        // 检查录音时长
        if recordingDuration >= 1.0 {
            // 录音时长足够，发送
            onSendVoice(url, recordingDuration)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // 录音时长太短，删除文件
            try? FileManager.default.removeItem(at: url)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        
        cleanup()
    }
    
    private func cancelRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isRecording = false
            showRecordingTip = false
            voiceButtonScale = 1.0
        }
        
        // 删除录音文件
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        cleanup()
    }
    
    private func cleanup() {
        audioRecorder = nil
        recordingURL = nil
        recordingStartTime = nil
        recordingDuration = 0
    }
}

// MARK: - 增强语音消息气泡
struct EnhancedVoiceMessageBubble: View {
    let voiceURL: String
    let duration: TimeInterval
    let isFromMe: Bool
    
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    @State private var waveformPhase: Double = 0
    @State private var resolvedDuration: TimeInterval?
    
    var body: some View {
        HStack(spacing: 12) {
            // 播放按钮
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(isFromMe ? Color.white.opacity(0.2) : Color.blue)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isFromMe ? .white : .white)
                        .symbolEffect(.bounce, value: isPlaying)
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                // 波形显示
                HStack(spacing: 2) {
                    ForEach(0..<15, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(waveformColor(for: index))
                            .frame(width: 3, height: waveformHeight(for: index))
                            .animation(
                                .easeInOut(duration: 0.4)
                                    .delay(Double(index) * 0.05)
                                    .repeatCount(isPlaying ? .max : 1, autoreverses: true),
                                value: waveformPhase
                            )
                    }
                }
                .frame(height: 24)
                
                // 时间显示
                HStack {
                    Text(formatTime(isPlaying ? currentTime : (resolvedDuration ?? duration)))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isFromMe ? .white.opacity(0.8) : .secondary)
                        .monospacedDigit()
                    
                    if isPlaying {
                        Spacer()
                        
                        Text("/ \(formatTime(resolvedDuration ?? duration))")
                            .font(.caption)
                            .foregroundStyle(isFromMe ? .white.opacity(0.6) : .secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isFromMe ? 
                    LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                    LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .onAppear {
            waveformPhase = Double.random(in: 0...1)
            if duration <= 0 { Task { await resolveDurationIfNeeded() } }
        }
        .onDisappear {
            stopPlayback()
        }
    }
    
    private func waveformColor(for index: Int) -> Color {
        let progress = duration > 0 ? currentTime / duration : 0
        let indexProgress = Double(index) / 14.0
        
        if isPlaying && indexProgress <= progress {
            return isFromMe ? .white : .blue
        } else {
            return isFromMe ? .white.opacity(0.4) : .gray.opacity(0.6)
        }
    }
    
    private func waveformHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 24
        
        // 模拟音频波形
        let waveValue = sin(Double(index) * 0.5 + waveformPhase * 2) * 0.5 + 0.5
        let playbackMultiplier = isPlaying ? 1.5 : 1.0
        
        return baseHeight + (maxHeight - baseHeight) * CGFloat(waveValue) * CGFloat(playbackMultiplier)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            Task { await startPlayback() }
        }
    }
    
    private func startPlayback() async {
        guard let url = URL(string: voiceURL) else { return }
        
        do {
            if url.isFileURL {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
            } else {
                let (data, _) = try await URLSession.shared.data(from: url)
                audioPlayer = try AVAudioPlayer(data: data)
            }
            audioPlayer?.play()

            resolvedDuration = audioPlayer?.duration
            isPlaying = true
            currentTime = 0
            
            withAnimation(.easeInOut(duration: 0.5)) {
                waveformPhase += 1
            }
            
            // 启动播放计时器
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                guard let player = audioPlayer else { return }
                
                currentTime = player.currentTime
                
                if !player.isPlaying {
                    stopPlayback()
                }
            }
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
        } catch {
            print("❌ 语音播放失败: \(error)")
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPlaying = false
            currentTime = 0
        }
    }

    private func resolveDurationIfNeeded() async {
        guard resolvedDuration == nil, let url = URL(string: voiceURL) else { return }
        do {
            if url.isFileURL {
                let player = try AVAudioPlayer(contentsOf: url)
                resolvedDuration = player.duration
            } else {
                let (data, _) = try await URLSession.shared.data(from: url)
                let player = try AVAudioPlayer(data: data)
                resolvedDuration = player.duration
            }
        } catch {
            // 忽略解析错误，保持默认时长
            print("⚠️ 解析语音时长失败: \(error)")
        }
    }
}

// MARK: - 辅助组件

private struct ScaleButtonStyle: ButtonStyle {
    let scale: CGFloat
    
    init(scale: CGFloat = 0.95) {
        self.scale = scale
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 音频录制代理
private class AudioRecorderDelegate: NSObject, AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🎤 录音完成: \(flag ? "成功" : "失败")")
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ 录音编码错误: \(error?.localizedDescription ?? "未知错误")")
    }
}

#Preview {
    VStack {
        Spacer()
        
        EnhancedVoiceInputBar(
            text: .constant(""),
            showKeyboard: .constant(false),
            onSendText: {
                print("发送文本消息")
            },
            onSendVoice: { url, duration in
                print("发送语音消息: \(url), 时长: \(duration)秒")
            }
        )
    }
    .background(Color(.systemBackground))
}