//
//  ProfileVisitorsView.swift
//  Melodii
//
//  主页访客列表视图 - 显示谁访问过我的主页
//

import SwiftUI

struct ProfileVisitorsView: View {
    let userId: String

    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var visits: [ProfileVisit] = []
    @State private var isLoading = false
    @State private var visitCount: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 访客统计卡片
                visitorStatsCard

                // 访客列表
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if visits.isEmpty {
                    emptyStateView
                } else {
                    visitorsListView
                }
            }
            .padding()
        }
        .navigationTitle("谁看过我")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .task {
            await loadVisits()
        }
        .refreshable {
            await loadVisits()
        }
    }

    // MARK: - Visitor Stats Card

    private var visitorStatsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("访客统计")
                    .font(.headline)

                Spacer()
            }

            HStack(spacing: 30) {
                StatItemView(
                    title: "总访客",
                    value: "\(visitCount)",
                    icon: "person.3.fill",
                    color: .blue
                )

                StatItemView(
                    title: "今日访客",
                    value: "\(todayVisitCount)",
                    icon: "calendar",
                    color: .green
                )

                StatItemView(
                    title: "本周访客",
                    value: "\(weekVisitCount)",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var todayVisitCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return visits.filter { calendar.isDate($0.visitedAt, inSameDayAs: today) }.count
    }

    private var weekVisitCount: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return visits.filter { $0.visitedAt >= weekAgo }.count
    }

    // MARK: - Visitors List

    private var visitorsListView: some View {
        VStack(spacing: 12) {
            ForEach(visits) { visit in
                if let visitor = visit.visitor {
                    NavigationLink(destination: UserProfileView(user: visitor)) {
                        VisitorRowView(visit: visit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .padding()

            Text("还没有人访问过")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("分享你的主页，让更多人了解你")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Data Loading

    private func loadVisits() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 获取访客列表
            visits = try await supabaseService.fetchProfileVisits(userId: userId)

            // 获取总访客数（使用访客列表的数量）
            visitCount = visits.count

            print("✅ 加载访客记录成功: \(visits.count) 条")
        } catch {
            print("❌ 加载访客记录失败: \(error)")
        }
    }
}

// MARK: - Visitor Row View

private struct VisitorRowView: View {
    let visit: ProfileVisit

    var body: some View {
        HStack(spacing: 16) {
            // 头像
            if let visitor = visit.visitor {
                Group {
                    if let avatarURL = visitor.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 56, height: 56)
                                    .overlay(ProgressView().scaleEffect(0.8))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                            case .failure:
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.7), .pink.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(visitor.initials)
                                            .font(.title3)
                                            .foregroundColor(.white)
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.7), .pink.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(visitor.initials)
                                    .font(.title3)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .overlay(
                    // 在线状态指示器
                    Circle()
                        .fill(visitor.isOnline ? Color.green : Color.gray)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                        .offset(x: 20, y: 20)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(visitor.nickname)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let mid = visitor.mid {
                        Text("MID: \(mid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("访问于 \(visit.visitedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Stat Item View

private struct StatItemView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ProfileVisitorsView(userId: "test-user-id")
    }
}
