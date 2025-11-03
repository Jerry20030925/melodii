//
//  Card3DView.swift
//  Melodii
//
//  独特的3D卡片效果 - 让每个帖子都像一张精美的卡片
//

import SwiftUI

/// 3D卡片容器，提供深度感和交互性
struct Card3DView<Content: View>: View {
    let content: Content

    @State private var rotationX: Double = 0
    @State private var rotationY: Double = 0
    @State private var scale: CGFloat = 1.0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                // 动态渐变背景
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(.systemGray6).opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 10,
                x: 0,
                y: 5
            )
            .rotation3DEffect(
                .degrees(rotationX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.5
            )
            .rotation3DEffect(
                .degrees(rotationY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.5
            )
            .scaleEffect(scale)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            rotationY = Double(value.translation.width / 20)
                            rotationX = -Double(value.translation.height / 20)
                            scale = 0.98
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                            rotationX = 0
                            rotationY = 0
                            scale = 1.0
                        }
                    }
            )
            .onAppear {
                withAnimation(
                    .spring(response: 0.6, dampingFraction: 0.7)
                    .delay(Double.random(in: 0...0.2))
                ) {
                    scale = 1.0
                }
            }
    }
}

/// 粒子动画背景 - 增加视觉趣味
struct ParticleBackground: View {
    @State private var particles: [Particle] = []
    let particleCount = 20

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color.opacity(0.3))
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .blur(radius: 3)
            }
        }
        .onAppear {
            createParticles()
            startAnimation()
        }
    }

    private func createParticles() {
        particles = (0..<particleCount).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                ),
                size: CGFloat.random(in: 20...60),
                color: [Color.blue, Color.purple, Color.pink].randomElement()!
            )
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.linear(duration: 0.05)) {
                for i in 0..<particles.count {
                    particles[i].position.y -= 0.5
                    particles[i].position.x += CGFloat.random(in: -1...1)

                    if particles[i].position.y < -50 {
                        particles[i].position.y = UIScreen.main.bounds.height + 50
                        particles[i].position.x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
                    }
                }
            }
        }
    }
}

private struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    let size: CGFloat
    let color: Color
}

#Preview {
    Card3DView {
        VStack {
            Text("3D卡片效果")
                .font(.title)
            Text("拖动试试看")
                .font(.caption)
        }
        .padding(40)
    }
    .padding()
}
