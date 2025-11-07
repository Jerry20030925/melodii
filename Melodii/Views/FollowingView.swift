//
//  FollowingView.swift
//  Melodii
//
//  关注视图
//

import SwiftUI

struct FollowingView: View {
    let posts: [Post]
    
    @State private var refreshing = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            if posts.isEmpty {
                emptyFollowingView
            } else {
                followingPostsList
            }
        }
        .refreshable {
            await refresh()
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("关注动态")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("来自你关注的人的最新动态")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatCount(refreshing ? 10 : 0), value: refreshing)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var followingPostsList: some View {
        LazyVStack(spacing: 16) {
            ForEach(posts) { post in
                PostCardView(post: post)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private var emptyFollowingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 80))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 12) {
                Text("还没有关注任何人")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("关注感兴趣的用户，查看他们的最新动态")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                NavigationLink("发现用户") {
                    // 用户发现页面
                    Text("用户发现")
                }
                .buttonStyle(.borderedProminent)
                
                Button("浏览推荐内容") {
                    // 切换到推荐
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private func refresh() async {
        refreshing = true
        // 模拟刷新延迟
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        refreshing = false
    }
}

#Preview {
    FollowingView(posts: [])
}