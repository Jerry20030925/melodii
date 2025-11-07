// Simple test implementation for debugging
import Foundation
import Supabase

extension SupabaseService {
    
    // Ultra-simple test message sending
    func sendMessageSimple(conversationId: String, senderId: String, content: String) async throws {
        print("🔍 [SIMPLE] Starting simple message send...")
        
        // Use an Encodable payload instead of [String: Any]
        struct MessageInsert: Encodable {
            let conversation_id: String
            let sender_id: String
            let receiver_id: String
            let content: String
            let message_type: String
            let is_read: Bool
        }
        
        let insertData = MessageInsert(
            conversation_id: conversationId,
            sender_id: senderId,
            receiver_id: senderId, // For now, just use same user to test insert
            content: content,
            message_type: "text",
            is_read: false
        )
        
        do {
            print("🔍 [SIMPLE] Inserting basic message...")
            let response = try await client
                .from("messages")
                .insert(insertData)
                .execute()
            print("✅ [SIMPLE] Message inserted successfully!")
            print("🔍 [SIMPLE] Response: \(response)")
        } catch {
            print("❌ [SIMPLE] Insert failed: \(error)")
            print("❌ [SIMPLE] Error details: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Test if we can query conversations
    func testConversationExists(conversationId: String) async throws -> Bool {
        print("🔍 [TEST] Checking if conversation exists: \(conversationId)")
        
        do {
            let count: Int = try await client
                .from("conversations")
                .select("id", head: true, count: .exact)
                .eq("id", value: conversationId)
                .execute()
                .count ?? 0
            
            print("🔍 [TEST] Conversation count: \(count)")
            return count > 0
        } catch {
            print("❌ [TEST] Conversation check failed: \(error)")
            return false
        }
    }
}
