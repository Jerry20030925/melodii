//
//  SupabaseConfig.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import Supabase

enum SupabaseConfig {
    // TODO: 替换为您的Supabase项目URL和API Key
    static let url = "https://tlqqgdvgtwdietsxxmwf.supabase.co" // 例如: https://xxxxx.supabase.co
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRscXFnZHZndHdkaWV0c3h4bXdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjE3OTM3NTQsImV4cCI6MjA3NzM2OTc1NH0.64pFGERsQyAptZzved4Ojb3wfx7tMwAVMK0l2h8G34w"

    // 兼容 Supabase RFC3339（含小数秒）的 ISO8601 格式化器
    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [
            .withInternetDateTime,        // 基本 RFC 3339
            .withFractionalSeconds        // 兼容可变长度小数秒
        ]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // 统一 JSONDecoder/Encoder，避免 Date 解码失败
    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // 自定义 date 解码，优先使用带小数秒的 ISO8601
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // 先尝试带小数秒
            if let date = rfc3339Formatter.date(from: str) {
                return date
            }
            // 再尝试不含小数秒
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: str) {
                return date
            }
            // 最后尝试标准解码（以防万一）
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }
        return decoder
    }

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let string = rfc3339Formatter.string(from: date)
            try container.encode(string)
        }
        return encoder
    }

    static let client: SupabaseClient = {
        // 将自定义编解码器注入到数据库子客户端和（可选）Auth 子客户端
        let dbOptions = SupabaseClientOptions.DatabaseOptions(
            schema: nil,
            encoder: makeJSONEncoder(),
            decoder: makeJSONDecoder()
        )

        // 如果也需要在 Auth 中统一日期编解码，可取消注释下面这段：
        // let authOptions = SupabaseClientOptions.AuthOptions(
        //     storage: AuthClient.Configuration.defaultLocalStorage,
        //     redirectToURL: nil,
        //     storageKey: nil,
        //     flowType: AuthClient.Configuration.defaultFlowType,
        //     encoder: makeJSONEncoder(),
        //     decoder: makeJSONDecoder(),
        //     autoRefreshToken: AuthClient.Configuration.defaultAutoRefreshToken,
        //     accessToken: nil
        // )

        // 非 Linux/Android 平台可以使用无 storage 参数的便捷 init
        var options = SupabaseClientOptions(
            db: dbOptions
            // , auth: authOptions // 如果上面自定义了 AuthOptions，则改用通用 init 版本
        )

        return SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey,
            options: options
        )
    }()
}
