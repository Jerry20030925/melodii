//
//  SearchView.swift
//  Melodii
//
//  搜索用户功能 - 通过 MID 或昵称
//

import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var searchText = ""
    @State private var searchResults: [User] = []
    @State private var isSearching = false
    @State private var searchHistory: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                searchBar

                // 搜索结果或历史
                if searchText.isEmpty {
                    searchHistoryView
                } else if isSearching {
                    loadingView
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    emptyResultView
                } else {
                    searchResultsView
                }
            }
            .navigationTitle("搜索用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSearchHistory()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索 MID 或昵称", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    Task { await performSearch() }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    // MARK: - Search History

    private var searchHistoryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !searchHistory.isEmpty {
                    HStack {
                        Text("搜索历史")
                            .font(.headline)
                        Spacer()
                        Button("清空") {
                            searchHistory = []
                            saveSearchHistory()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                    }

                    ForEach(searchHistory, id: \.self) { keyword in
                        Button {
                            searchText = keyword
                            Task { await performSearch() }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                Text(keyword)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("搜索 MID 或昵称找到用户")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }
            }
            .padding()
        }
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults) { user in
                    NavigationLink {
                        UserProfileView(user: user)
                    } label: {
                        UserSearchResultCard(user: user)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    // MARK: - Loading & Empty

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("搜索中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var emptyResultView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("没有找到用户")
                .font(.headline)

            Text("试试搜索其他关键词")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Search Logic

    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSearching = true

        do {
            // 搜索用户
            searchResults = try await supabaseService.searchUsers(keyword: searchText, limit: 50)

            // 添加到搜索历史
            if !searchHistory.contains(searchText) {
                searchHistory.insert(searchText, at: 0)
                if searchHistory.count > 10 {
                    searchHistory = Array(searchHistory.prefix(10))
                }
                saveSearchHistory()
            }
        } catch {
            print("❌ 搜索失败: \(error)")
        }

        isSearching = false
    }

    // MARK: - Search History Storage

    private func loadSearchHistory() {
        if let saved = UserDefaults.standard.stringArray(forKey: "searchHistory") {
            searchHistory = saved
        }
    }

    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: "searchHistory")
    }
}

// MARK: - User Search Result Card

struct UserSearchResultCard: View {
    let user: User
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared

    @State private var isFollowing = false

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Text(user.initials)
                        .font(.headline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(user.nickname)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text("MID: \(user.mid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !user.interests.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(user.interests.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 关注按钮
            if user.id != authService.currentUser?.id {
                Button {
                    Task { await toggleFollow() }
                } label: {
                    Text(isFollowing ? "已关注" : "关注")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isFollowing ? .secondary : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(isFollowing ? Color(.systemGray5) : Color.blue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        .task {
            await loadFollowStatus()
        }
    }

    private func loadFollowStatus() async {
        guard let userId = authService.currentUser?.id else { return }
        do {
            isFollowing = try await supabaseService.isFollowing(followerId: userId, followingId: user.id)
        } catch {
            print("加载关注状态失败: \(error)")
        }
    }

    private func toggleFollow() async {
        guard let userId = authService.currentUser?.id else { return }

        let wasFollowing = isFollowing
        isFollowing.toggle()

        do {
            if isFollowing {
                try await supabaseService.followUser(followerId: userId, followingId: user.id)
            } else {
                try await supabaseService.unfollowUser(followerId: userId, followingId: user.id)
            }
        } catch {
            isFollowing = wasFollowing
            print("关注操作失败: \(error)")
        }
    }
}

#Preview {
    SearchView()
}
