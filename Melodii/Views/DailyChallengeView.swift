//
//  DailyChallengeView.swift
//  Melodii
//
//  每日挑战系统 - 游戏化激励，提高用户活跃度
//

import SwiftUI

struct DailyChallengeView: View {
    @State private var challenges: [Challenge] = Challenge.daily
    @State private var completedChallenges: Set<String> = []
    @State private var streak: Int = 0
    @State private var totalPoints: Int = 0
    @State private var showReward = false
    @State private var earnedReward: Reward?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 连续打卡
                streakSection

                // 今日挑战
                challengesSection

                // 成就展示
                achievementsSection

                // 排行榜入口
                leaderboardSection
            }
            .padding()
        }
        .navigationTitle("每日挑战")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showReward) {
            if let reward = earnedReward {
                RewardSheet(reward: reward)
            }
        }
        .onAppear {
            loadProgress()
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(spacing: 16) {
            // 火焰动画
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60 - CGFloat(index * 15)))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red, .pink],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(1.0 - Double(index) * 0.3)
                        .scaleEffect(1.0 + Double(index) * 0.1)
                }
            }
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text("\(streak)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("天连续打卡")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("总积分: \(totalPoints)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.1),
                            Color.red.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    // MARK: - Challenges Section

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日挑战")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                Text("\(completedChallenges.count)/\(challenges.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(challenges) { challenge in
                ChallengeCard(
                    challenge: challenge,
                    isCompleted: completedChallenges.contains(challenge.id),
                    onComplete: {
                        completeChallenge(challenge)
                    }
                )
            }
        }
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("成就")
                .font(.title3)
                .fontWeight(.bold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Achievement.allAchievements) { achievement in
                        AchievementBadge(
                            achievement: achievement,
                            isUnlocked: achievement.isUnlocked(streak: streak, points: totalPoints)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: some View {
        Button {
            // TODO: 打开排行榜
        } label: {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text("查看排行榜")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("看看你的排名")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods

    private func completeChallenge(_ challenge: Challenge) {
        guard !completedChallenges.contains(challenge.id) else { return }

        completedChallenges.insert(challenge.id)
        totalPoints += challenge.points

        // 检查是否完成所有挑战
        if completedChallenges.count == challenges.count {
            streak += 1
            earnedReward = Reward.dailyComplete
            showReward = true
        }

        // 触觉反馈
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // TODO: 保存进度
    }

    private func loadProgress() {
        // TODO: 从本地或服务器加载
        streak = 0
        totalPoints = 0
        completedChallenges = []
    }
}

// MARK: - Challenge Card

private struct ChallengeCard: View {
    let challenge: Challenge
    let isCompleted: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(
                        isCompleted
                        ? LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: isCompleted ? "checkmark" : challenge.icon)
                    .font(.title3)
                    .foregroundStyle(isCompleted ? .white : .secondary)
            }

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)

                Text(challenge.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 积分
            if !isCompleted {
                VStack(spacing: 2) {
                    Text("+\(challenge.points)")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("积分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isCompleted
                    ? Color(.systemGray6).opacity(0.5)
                    : Color(.systemBackground)
                )
                .shadow(
                    color: isCompleted ? .clear : .black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isCompleted ? Color.green.opacity(0.3) : Color.clear,
                    lineWidth: 2
                )
        )
        .onTapGesture {
            if !isCompleted {
                onComplete()
            }
        }
    }
}

// MARK: - Achievement Badge

private struct AchievementBadge: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        isUnlocked
                        ? LinearGradient(
                            colors: [achievement.color, achievement.color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Text(achievement.emoji)
                    .font(.system(size: 30))
                    .grayscale(isUnlocked ? 0 : 1)
            }

            Text(achievement.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isUnlocked ? .primary : .secondary)

            Text(achievement.requirement)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
        .padding(.vertical, 8)
    }
}

// MARK: - Reward Sheet

private struct RewardSheet: View {
    let reward: Reward

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 奖励动画
            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Image(systemName: "sparkle")
                        .font(.title)
                        .foregroundStyle(.yellow)
                        .offset(
                            x: cos(Double(index) * .pi / 6) * 80,
                            y: sin(Double(index) * .pi / 6) * 80
                        )
                        .opacity(0.8)
                }

                Text(reward.emoji)
                    .font(.system(size: 100))
            }

            VStack(spacing: 12) {
                Text("🎉 恭喜！")
                    .font(.title)
                    .fontWeight(.bold)

                Text(reward.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(reward.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text("+\(reward.bonus) 积分")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.1))
                    )
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("太棒了！")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Models

struct Challenge: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let points: Int

    static let daily: [Challenge] = [
        Challenge(
            id: "post",
            title: "发布一条动态",
            description: "分享你的生活瞬间",
            icon: "square.and.pencil",
            points: 10
        ),
        Challenge(
            id: "like",
            title: "点赞5次",
            description: "给喜欢的内容点赞",
            icon: "heart",
            points: 5
        ),
        Challenge(
            id: "comment",
            title: "评论3次",
            description: "与他人互动交流",
            icon: "bubble.left",
            points: 15
        ),
        Challenge(
            id: "follow",
            title: "关注一个新朋友",
            description: "扩展你的社交圈",
            icon: "person.badge.plus",
            points: 10
        ),
        Challenge(
            id: "mood",
            title: "记录今日心情",
            description: "了解自己的情绪变化",
            icon: "face.smiling",
            points: 5
        )
    ]
}

struct Achievement: Identifiable {
    let id: String
    let name: String
    let emoji: String
    let requirement: String
    let color: Color
    let unlockCondition: (Int, Int) -> Bool

    func isUnlocked(streak: Int, points: Int) -> Bool {
        unlockCondition(streak, points)
    }

    static let allAchievements: [Achievement] = [
        Achievement(
            id: "first_day",
            name: "初来乍到",
            emoji: "👋",
            requirement: "完成首日挑战",
            color: .blue,
            unlockCondition: { streak, _ in streak >= 1 }
        ),
        Achievement(
            id: "week_warrior",
            name: "一周达人",
            emoji: "🔥",
            requirement: "连续打卡7天",
            color: .orange,
            unlockCondition: { streak, _ in streak >= 7 }
        ),
        Achievement(
            id: "month_master",
            name: "月度冠军",
            emoji: "👑",
            requirement: "连续打卡30天",
            color: .yellow,
            unlockCondition: { streak, _ in streak >= 30 }
        ),
        Achievement(
            id: "point_hunter",
            name: "积分猎人",
            emoji: "💎",
            requirement: "累计100积分",
            color: .purple,
            unlockCondition: { _, points in points >= 100 }
        ),
        Achievement(
            id: "legend",
            name: "传奇玩家",
            emoji: "⭐",
            requirement: "累计1000积分",
            color: .pink,
            unlockCondition: { _, points in points >= 1000 }
        )
    ]
}

struct Reward {
    let emoji: String
    let title: String
    let message: String
    let bonus: Int

    static let dailyComplete = Reward(
        emoji: "🎁",
        title: "完成今日所有挑战！",
        message: "你真棒！继续保持这个势头",
        bonus: 50
    )
}

#Preview {
    NavigationStack {
        DailyChallengeView()
    }
}
