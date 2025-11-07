//
//  PostCardView.swift
//  Melodii
//
//  Lightweight wrapper to keep existing call sites working.
//  It forwards to EnhancedPostCardView.
//

import SwiftUI

struct PostCardView: View {
    let post: Post

    var body: some View {
        EnhancedPostCardView(post: post)
    }
}
