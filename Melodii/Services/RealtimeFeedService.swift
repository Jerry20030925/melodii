import Foundation
import Supabase
import Combine

@MainActor
final class RealtimeFeedService: ObservableObject {
    static let shared = RealtimeFeedService()
    private let client = SupabaseConfig.client
    private var postsChannel: RealtimeChannelV2?

    private init() {}

    func subscribeToPosts(onInsert: @escaping (Post) -> Void) async {
        // 退订旧通道
        if let channel = postsChannel { await channel.unsubscribe(); postsChannel = nil }
        let channel = client.realtimeV2.channel("posts-feed")
        postsChannel = channel

        Task {
            for await change in channel.postgresChange(InsertAction.self, schema: "public", table: "posts") {
                do {
                    let post = try change.decodeRecord(as: Post.self, decoder: JSONDecoder())
                    onInsert(post)
                } catch {
                    print("⚠️ decode post insert failed: \(error)")
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("❌ subscribe posts-feed failed: \(error)")
        }
    }
}
