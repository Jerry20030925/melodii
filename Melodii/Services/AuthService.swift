//
//  AuthService.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import AuthenticationServices
import Supabase
import Combine

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var currentUser: User?
    @Published var isAuthenticated = false

    private let client = SupabaseConfig.client

    private init() {
        // 不在初始化时检查会话，避免阻塞启动
        // 会话检查将在 RootView 中异步执行
    }

    // MARK: - Session Management

    /// 检查当前会话状态
    func checkSession() async {
        print("🔍 开始检查会话状态")

        do {
            // 添加超时保护
            let session = try await withTimeout(seconds: 5) {
                try await self.client.auth.session
            }

            if let userId = session.user.id.uuidString as String? {
                print("✅ 找到有效会话，用户ID: \(userId)")

                // 从数据库加载用户信息
                do {
                    self.currentUser = try await withTimeout(seconds: 5) {
                        try await SupabaseService.shared.fetchUser(id: userId)
                    }
                    self.isAuthenticated = true
                    print("✅ 用户信息加载成功")

                    // 启动实时连接（会话/会话内）
                    await RealtimeService.shared.connect(userId: userId)
                    // 启动全局实时（新消息/通知 + 未读计数）
                    await RealtimeCenter.shared.connect(userId: userId)
                } catch {
                    print("⚠️ 加载用户信息失败: \(error)")
                    // 会话有效但无法加载用户信息，保持未认证状态
                    self.isAuthenticated = false
                    self.currentUser = nil
                }
            } else {
                print("ℹ️ 没有有效会话")
                self.isAuthenticated = false
                self.currentUser = nil
            }
        } catch {
            print("ℹ️ 会话检查失败（可能是首次启动）: \(error)")
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    /// 带超时的异步操作
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask {
                try await operation()
            }

            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "AuthService", code: -1001, userInfo: [NSLocalizedDescriptionKey: "操作超时"])
            }

            // 返回第一个完成的任务结果（安全解包）
            guard let result = try await group.next() else {
                group.cancelAll()
                throw NSError(domain: "AuthService", code: -1002, userInfo: [NSLocalizedDescriptionKey: "未知错误：任务未返回结果"])
            }
            group.cancelAll()
            return result
        }
    }

    /// 登出
    func signOut() async throws {
        // 断开实时连接
        await RealtimeService.shared.disconnect()
        await RealtimeCenter.shared.disconnect()

        do {
            try await withTimeout(seconds: 10) {
                try await self.client.auth.signOut()
            }
        } catch {
            // 即使登出失败，也重置本地状态，避免 UI 卡在已登录状态
            print("⚠️ 登出请求失败，重置本地状态: \(error)")
        }
        self.isAuthenticated = false
        self.currentUser = nil
        print("✅ 登出成功")
    }

    // MARK: - Email Authentication

    /// 使用邮箱注册
    func signUpWithEmail(email: String, password: String) async throws {
        print("🔐 开始邮箱注册: \(email)")

        do {
            let response = try await withTimeout(seconds: 15) {
                try await self.client.auth.signUp(
                    email: email,
                    password: password
                )
            }

            let userId = response.user.id.uuidString
            print("✅ Supabase 注册成功，用户ID: \(userId)")

            // 创建新用户
            let nickname = email.components(separatedBy: "@").first ?? "用户\(String(userId.prefix(6)))"

            let newUser = try await withTimeout(seconds: 10) {
                try await self.createUser(
                    id: userId,
                    appleUserId: nil,
                    nickname: nickname,
                    avatarURL: nil
                )
            }

            print("✅ 用户信息创建成功")
            self.currentUser = newUser
            self.isAuthenticated = true

            // 启动实时连接（会话/会话内 + 全局）
            await RealtimeService.shared.connect(userId: userId)
            await RealtimeCenter.shared.connect(userId: userId)
        } catch {
            print("❌ 邮箱注册失败: \(error)")
            throw error
        }
    }

    /// 使用邮箱登录
    func signInWithEmail(email: String, password: String) async throws {
        print("🔐 开始邮箱登录: \(email)")

        do {
            let response = try await withTimeout(seconds: 15) {
                try await self.client.auth.signIn(
                    email: email,
                    password: password
                )
            }

            let userId = response.user.id.uuidString
            print("✅ Supabase 登录成功，用户ID: \(userId)")

            // 从数据库加载用户信息
            do {
                let user = try await withTimeout(seconds: 10) {
                    try await SupabaseService.shared.fetchUser(id: userId)
                }
                print("✅ 用户信息加载成功")
                self.currentUser = user
            } catch {
                print("⚠️ 用户信息不存在，创建新用户")
                // 用户不存在，创建新用户（适配旧数据）
                let nickname = email.components(separatedBy: "@").first ?? "用户\(String(userId.prefix(6)))"

                let newUser = try await withTimeout(seconds: 10) {
                    try await self.createUser(
                        id: userId,
                        appleUserId: nil,
                        nickname: nickname,
                        avatarURL: nil
                    )
                }
                print("✅ 新用户信息创建成功")
                self.currentUser = newUser
            }

            self.isAuthenticated = true

            // 启动实时连接（会话/会话内 + 全局）
            await RealtimeService.shared.connect(userId: userId)
            await RealtimeCenter.shared.connect(userId: userId)
        } catch {
            print("❌ 邮箱登录失败: \(error)")
            throw error
        }
    }

    // MARK: - Apple Sign In

    /// 使用Apple登录
    func signInWithApple(idToken: String, nonce: String) async throws {
        print("🍎 开始 Apple 登录")
        print("🔑 ID Token 长度: \(idToken.count)")
        print("🔑 Nonce: \(nonce)")

        do {
            // 使用Supabase的Apple OAuth登录
            let session = try await withTimeout(seconds: 20) {
                try await self.client.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: idToken,
                        nonce: nonce
                    )
                )
            }

            let userId = session.user.id.uuidString
            print("✅ Apple 登录成功，用户ID: \(userId)")

            // 检查用户是否已存在
            do {
                let user = try await withTimeout(seconds: 10) {
                    try await SupabaseService.shared.fetchUser(id: userId)
                }
                print("✅ 用户信息加载成功")
                self.currentUser = user
            } catch {
                print("⚠️ 用户信息不存在，创建新用户")
                // 用户不存在，创建新用户
                let fullName = session.user.userMetadata["full_name"]?.stringValue
                let nickname = fullName ?? "用户\(String(userId.prefix(6)))"
                let avatarURL = session.user.userMetadata["avatar_url"]?.stringValue

                let newUser = try await withTimeout(seconds: 10) {
                    try await self.createUser(
                        id: userId,
                        appleUserId: session.user.id.uuidString,
                        nickname: nickname,
                        avatarURL: avatarURL
                    )
                }
                print("✅ 新用户信息创建成功")
                self.currentUser = newUser
            }

            self.isAuthenticated = true

            // 启动实时连接（会话/会话内 + 全局）
            await RealtimeService.shared.connect(userId: userId)
            await RealtimeCenter.shared.connect(userId: userId)
        } catch {
            print("❌ Apple 登录失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
            throw error
        }
    }

    /// 获取或等待触发器创建的用户
    private func createUser(id: String, appleUserId: String?, nickname: String, avatarURL: String?) async throws -> User {
        // ✅ Auth.signUp 后，触发器会自动创建 public.users 记录
        // ✅ 这里只需要等待并读取触发器创建的用户
        print("🔄 等待触发器创建用户...")

        // 最多重试 3 次，每次间隔 1 秒
        for attempt in 1...3 {
            do {
                let user: User = try await client
                    .from("users")
                    .select()
                    .eq("id", value: id)
                    .single()
                    .execute()
                    .value

                print("✅ 触发器已创建用户，MID: \(user.mid ?? "无")")
                return user
            } catch {
                print("⏳ 尝试 \(attempt)/3: 用户尚未创建，等待 1 秒...")
                if attempt < 3 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒
                } else {
                    throw NSError(
                        domain: "AuthService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "触发器创建用户超时，请检查数据库触发器配置"]
                    )
                }
            }
        }

        throw NSError(
            domain: "AuthService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "无法获取用户信息"]
        )
    }

    // MARK: - Password Reset

    /// 发送密码重置邮件
    func sendPasswordReset(email: String, redirectTo: URL? = nil) async throws {
        try await withTimeout(seconds: 15) {
            try await self.client.auth.resetPasswordForEmail(email, redirectTo: redirectTo)
        }
    }
}

// MARK: - Apple Sign In Coordinator

class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var currentNonce: String?
    private var continuation: CheckedContinuation<(idToken: String, nonce: String), Error>?

    func signIn() async throws -> (idToken: String, nonce: String) {
        // 为授权流程增加超时保护，避免挂起
        let result = try await withThrowingTaskGroup(of: (idToken: String, nonce: String).self) { group in
            // 授权任务
            group.addTask { [weak self] in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(idToken: String, nonce: String), Error>) in
                    guard let self else {
                        continuation.resume(throwing: NSError(domain: "AppleSignIn", code: -3, userInfo: [NSLocalizedDescriptionKey: "授权上下文已释放"]))
                        return
                    }
                    self.continuation = continuation

                    let nonce = (try? self.randomNonceString()) ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    self.currentNonce = nonce

                    let appleIDProvider = ASAuthorizationAppleIDProvider()
                    let request = appleIDProvider.createRequest()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = self.sha256(nonce)

                    let authorizationController = ASAuthorizationController(authorizationRequests: [request])
                    authorizationController.delegate = self
                    authorizationController.presentationContextProvider = self
                    authorizationController.performRequests()
                }
            }

            // 超时任务（例如 60 秒）
            group.addTask {
                try await Task.sleep(nanoseconds: 60 * NSEC_PER_SEC)
                throw NSError(domain: "AppleSignIn", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Apple 登录超时"])
            }

            guard let value = try await group.next() else {
                group.cancelAll()
                throw NSError(domain: "AppleSignIn", code: -1002, userInfo: [NSLocalizedDescriptionKey: "Apple 登录未知错误"])
            }
            group.cancelAll()
            return value
        }

        return result
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let idTokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            continuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"]))
            continuation = nil
            return
        }

        continuation?.resume(returning: (idToken: idTokenString, nonce: nonce))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        if let window = scenes.first?.windows.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first {
            return window
        }
        let tempWindow = UIWindow(frame: UIScreen.main.bounds)
        tempWindow.windowLevel = .alert + 1
        return tempWindow
        #else
        return ASPresentationAnchor()
        #endif
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = try (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    throw NSError(domain: "AppleSignIn", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "随机数生成失败: \(status)"])
                }
                return random
            }

            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = inputData.sha256()
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}

// MARK: - Data Extension for SHA256
import CryptoKit

extension Data {
    func sha256() -> Data {
        return Data(SHA256.hash(data: self))
    }
}
