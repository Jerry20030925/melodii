//
//  VoiceRecorderView.swift
//  Melodii
//
//  语音录制界面
//

import SwiftUI

struct VoiceRecorderView: View {
    @ObservedObject private var recorder = AudioRecorder.shared
    @Binding var isPresented: Bool

    let onSend: (URL) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isCancelling = false

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelRecording()
                }

            VStack {
                Spacer()

                // 录音界面
                recordingCard
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    dragOffset = value.translation.height
                                    isCancelling = dragOffset > 100
                                }
                            }
                            .onEnded { value in
                                if dragOffset > 100 {
                                    cancelRecording()
                                } else {
                                    withAnimation(.spring()) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .transition(.opacity)
    }

    private var recordingCard: some View {
        VStack(spacing: 24) {
            // 取消提示
            if isCancelling {
                Text("松开手指取消")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            }

            // 音量波形
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4)
                        .frame(height: waveHeight(for: index))
                        .animation(
                            .easeInOut(duration: 0.3)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.05),
                            value: recorder.audioLevel
                        )
                }
            }
            .frame(height: 80)

            // 录音时长
            Text(recorder.formatTime(recorder.recordingTime))
                .font(.system(size: 48, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            // 按钮组
            HStack(spacing: 40) {
                // 取消按钮
                Button {
                    withAnimation {
                        cancelRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 60)

                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(ScaleButtonStyle())

                // 完成按钮
                Button {
                    withAnimation {
                        finishRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)

                        Image(systemName: "checkmark")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(recorder.recordingTime < 1) // 至少录制1秒
            }

            Text("向下滑动取消")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 20
        let maxHeight: CGFloat = 80

        // 使用音量级别来计算高度
        let levelMultiplier = CGFloat(recorder.audioLevel)

        // 添加一些随机性，让波形更自然
        let randomFactor = CGFloat.random(in: 0.7...1.0)

        return baseHeight + (maxHeight - baseHeight) * levelMultiplier * randomFactor
    }

    private func cancelRecording() {
        recorder.cancelRecording()
        isPresented = false
    }

    private func finishRecording() {
        if let url = recorder.stopRecording() {
            onSend(url)
        }
        isPresented = false
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    VoiceRecorderView(isPresented: .constant(true)) { url in
        print("Voice recording saved to: \(url)")
    }
}
