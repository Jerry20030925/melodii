//
//  EditProfileView.swift
//  Melodii
//
//  编辑个人资料 - 头像、背景图、昵称
//

import SwiftUI
import PhotosUI
import Supabase
import PostgREST

struct EditProfileView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var storageService = StorageService.shared

    @State private var nickname: String
    @State private var bio: String
    @State private var interests: [String]
    @State private var interestInput = ""
    
    // MID编辑相关
    @State private var mid: String
    @State private var isEditingMid = false
    @State private var midValidationResult: MIDValidationResult?

    // 头像
    @State private var avatarImage: UIImage?
    @State private var selectedAvatarItem: PhotosPickerItem?

    // 背景图
    @State private var coverImage: UIImage?
    @State private var selectedCoverItem: PhotosPickerItem?

    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    init(user: User) {
        self.user = user
        _nickname = State(initialValue: user.nickname)
        _bio = State(initialValue: user.bio ?? "")
        _interests = State(initialValue: user.interests)
        _mid = State(initialValue: user.mid ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    coverImageSection
                    avatarSection
                        .offset(y: -50)
                    basicInfoSection
                        .padding(.horizontal, 20)
                    interestsSection
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        if isSaving { ProgressView() }
                        else { Text("保存").fontWeight(.semibold) }
                    }
                    .disabled(isSaving || nickname.isEmpty)
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {
                    if alertMessage.contains("成功") { dismiss() }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    // MARK: - Cover Image Section

    private var coverImageSection: some View {
        ZStack(alignment: .bottom) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .pink.opacity(0.3), .orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
            }

            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    Text("更换封面")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())
            }
            .padding(.bottom, 12)
        }
        .frame(height: 180)
        .onChange(of: selectedCoverItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    coverImage = image
                }
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack {
            ZStack(alignment: .bottomTrailing) {
                if let avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.8), .pink.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(user.initials)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }

                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                }
            }
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 4)
            )
        }
        .onChange(of: selectedAvatarItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarImage = image
                }
            }
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 昵称输入
            VStack(alignment: .leading, spacing: 8) {
                Text("昵称")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("输入昵称", text: $nickname)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // MID编辑
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("MID")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if user.canUpdateMid {
                        Button(isEditingMid ? "取消" : "编辑") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isEditingMid.toggle()
                                if !isEditingMid {
                                    // 取消编辑，恢复原值
                                    mid = user.mid ?? ""
                                    midValidationResult = nil
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }
                
                if isEditingMid {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("输入MID（英文数字，最多8位）", text: $mid)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                midValidationResult?.isValid == false ? Color.red.opacity(0.5) : Color.clear,
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .onChange(of: mid) { _, newValue in
                                let formatted = newValue.formattedMID
                                if formatted != newValue {
                                    mid = formatted
                                }
                                midValidationResult = MIDValidationResult(input: formatted)
                            }
                        
                        if let validationResult = midValidationResult,
                           !validationResult.isValid,
                           let errorMessage = validationResult.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        
                        Text("• 仅支持英文字母和数字\n• 最多8个字符\n• 每半年只能修改一次")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mid.isEmpty ? "未设置" : mid)
                            .font(.body)
                            .foregroundColor(mid.isEmpty ? .secondary : .blue)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        if !user.canUpdateMid {
                            if let waitTime = MIDUpdateFrequencyChecker.remainingWaitTimeDescription(lastUpdateDate: user.lastMidUpdate) {
                                Text(waitTime)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            // 个人简介
            VStack(alignment: .leading, spacing: 8) {
                Text("个人简介")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextEditor(text: $bio)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Interests Section

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("兴趣标签")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if !interests.isEmpty {
                FlowLayoutSimple(interests) { interest in
                    HStack(spacing: 6) {
                        Text(interest)
                            .font(.subheadline)
                        Button {
                            interests.removeAll { $0 == interest }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
                }
                .frame(height: 80)
            }

            HStack {
                TextField("添加兴趣", text: $interestInput)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    addInterest()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(interestInput.isEmpty)
            }
        }
    }

    // MARK: - Helper Methods

    private func addInterest() {
        let trimmed = interestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !interests.contains(trimmed) else { return }
        interests.append(trimmed)
        interestInput = ""
    }

    private func saveProfile() async {
        guard !nickname.isEmpty else {
            alertMessage = "昵称不能为空"
            showAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }
        print("🔄 开始保存个人资料...")

        do {
            var avatarURL: String? = nil
            var coverURL: String? = nil

            if let avatarImage, let data = avatarImage.jpegData(compressionQuality: 0.9) {
                avatarURL = try await supabaseService.uploadChatMedia(
                    data: data,
                    mime: "image/jpeg",
                    fileName: "avatar_\(user.id).jpg",
                    folder: "avatars/\(user.id)",
                    bucket: "media",
                    isPublic: true
                )
            }

            if let coverImage, let data = coverImage.jpegData(compressionQuality: 0.9) {
                coverURL = try await supabaseService.uploadChatMedia(
                    data: data,
                    mime: "image/jpeg",
                    fileName: "cover_\(user.id).jpg",
                    folder: "covers/\(user.id)",
                    bucket: "media",
                    isPublic: true
                )
            }

            // 更新MID（如果有修改且验证通过）
            if isEditingMid && mid != (user.mid ?? "") {
                // 验证MID
                let validationResult = MIDValidationResult(input: mid)
                guard validationResult.isValid else {
                    alertMessage = validationResult.errorMessage ?? "MID格式无效"
                    showAlert = true
                    return
                }
                
                // 检查修改频率
                guard user.canUpdateMid else {
                    alertMessage = "MID修改过于频繁，请稍后再试"
                    showAlert = true
                    return
                }
                
                try await supabaseService.updateUserMID(
                    userId: user.id,
                    newMID: mid
                )
                
                isEditingMid = false
            }

            try await supabaseService.updateUser(
                id: user.id,
                nickname: nickname,
                bio: bio.isEmpty ? nil : bio,
                avatarURL: avatarURL ?? user.avatarURL,
                coverURL: coverURL ?? user.coverImageURL,
                interests: interests  // 现在支持interests参数
            )

            if let currentUser = authService.currentUser {
                currentUser.nickname = nickname
                currentUser.bio = bio.isEmpty ? nil : bio
                currentUser.interests = interests
                currentUser.avatarURL = avatarURL ?? currentUser.avatarURL
                currentUser.coverImageURL = coverURL ?? currentUser.coverImageURL
                
                // 更新MID相关信息
                if isEditingMid && mid != (user.mid ?? "") {
                    currentUser.mid = mid
                    currentUser.lastMidUpdate = Date()
                }
            }

            alertMessage = "保存成功！"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

#Preview {
    EditProfileView(user: User(id: "123", mid: "M123456", nickname: "测试用户"))
}
