//
//  OnboardingView.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    @State private var currentStep = 0
    @State private var birthday: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var selectedInterests: Set<String> = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    let availableInterests = [
        "运动", "游戏", "旅行", "电影", "美食",
        "摄影", "阅读", "科技", "时尚", "动漫",
        "艺术", "健身", "宠物", "绘画", "编程"
    ]

    var body: some View {
        ZStack {
            // 白色背景
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 进度指示器
                HStack(spacing: 8) {
                    ForEach(0..<2) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index <= currentStep ? Color.black : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 60)

                // 内容区域
                TabView(selection: $currentStep) {
                    // 步骤1：生日
                    birthdayStep
                        .tag(0)

                    // 步骤2：兴趣爱好
                    interestsStep
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            // 加载指示器
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - 生日步骤

    private var birthdayStep: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 15) {
                Text("你的生日是？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)

                Text("这将帮助我们为你推荐合适的内容")
                    .font(.body)
                    .foregroundStyle(.gray)
            }

            // 日期选择器
            DatePicker(
                "选择生日",
                selection: $birthday,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .colorScheme(.light)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 40)

            Spacer()

            // 下一步按钮
            Button(action: {
                withAnimation {
                    currentStep = 1
                }
            }) {
                Text("下一步")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.black)
                    .cornerRadius(25)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - 兴趣爱好步骤

    private var interestsStep: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 15) {
                Text("您的兴趣是？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.black)

                Text("选择至少3个你喜欢的兴趣类型")
                    .font(.body)
                    .foregroundStyle(.gray)
            }

            // 兴趣选择器
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(availableInterests, id: \.self) { interest in
                        InterestButton(
                            title: interest,
                            isSelected: selectedInterests.contains(interest)
                        ) {
                            toggleInterest(interest)
                        }
                    }
                }
                .padding(.horizontal, 40)
            }
            .frame(maxHeight: 300)

            Spacer()

            VStack(spacing: 15) {
                // 返回按钮
                Button(action: {
                    withAnimation {
                        currentStep = 0
                    }
                }) {
                    Text("返回")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(25)
                }

                // 完成按钮
                Button(action: {
                    completeOnboarding()
                }) {
                    Text("完成")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.black)
                        .cornerRadius(25)
                }
                .disabled(selectedInterests.count < 3)
                .opacity(selectedInterests.count < 3 ? 0.5 : 1)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Helper Functions

    private func toggleInterest(_ interest: String) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
        }
    }

    private func completeOnboarding() {
        guard let user = authService.currentUser else { return }

        isLoading = true

        Task {
            do {
                // 更新用户信息
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime]
                let birthdayString = dateFormatter.string(from: birthday)
                
                try await supabaseService.updateUserOnboardingInfo(
                    userId: user.id,
                    birthday: birthdayString,
                    interests: Array(selectedInterests)
                )

                // 更新本地用户状态
                user.birthday = birthday
                user.interests = Array(selectedInterests)
                user.isOnboardingCompleted = true

                isLoading = false
            } catch {
                isLoading = false
                errorMessage = "保存失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - 兴趣按钮组件

struct InterestButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.black : Color.gray.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.3), lineWidth: isSelected ? 0 : 1)
                )
        }
    }
}

#Preview {
    OnboardingView()
}

