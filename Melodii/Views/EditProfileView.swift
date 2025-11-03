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

            VStack(alignment: .leading, spacing: 8) {
                Text("MID（不可修改）")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(user.mid ?? "未设置")
                    .font(.body)
                    .foregroundColor(.blue)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

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

            try await supabaseService.updateUser(
                id: user.id,
                nickname: nickname,
                bio: bio.isEmpty ? nil : bio,
                avatarURL: avatarURL ?? user.avatarURL,
                coverURL: coverURL ?? user.coverImageURL
            )

            struct ExtraUserUpdates: Encodable {
                let interests: [String]
                let updated_at: String
            }
            let extras = ExtraUserUpdates(
                interests: interests,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )

            try await SupabaseConfig.client
                .from("users")
                .update(extras)
                .eq("id", value: user.id)
                .execute()

            if let currentUser = authService.currentUser {
                currentUser.nickname = nickname
                currentUser.bio = bio.isEmpty ? nil : bio
                currentUser.interests = interests
                currentUser.avatarURL = avatarURL ?? currentUser.avatarURL
                currentUser.coverImageURL = coverURL ?? currentUser.coverImageURL
            }

            alertMessage = "保存成功！"
            showAlert = true
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
            showAlert = true
        }

        isSaving = false
    }
}

#Preview {
    EditProfileView(user: User(id: "123", mid: "M123456", nickname: "测试用户"))
}
