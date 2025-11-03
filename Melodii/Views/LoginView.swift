//
//  LoginView.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showEmailLogin = false
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            // 白色背景
            Color.white
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 40) {
                    Spacer()
                        .frame(height: 80)

                    // Logo和标题
                    VStack(spacing: 25) {
                        Text("M")
                            .font(.system(size: 100, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)

                        Text("Melodii")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.8))

                        Text("分享你，分享你的世界")
                            .font(.body)
                            .foregroundStyle(.gray)
                    }

                    Spacer()
                        .frame(height: 40)

                    // 登录按钮区域
                    VStack(spacing: 16) {
                        // Apple Sign In 按钮
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                let nonce = randomNonceString()
                                currentNonce = nonce
                                request.requestedScopes = [.fullName, .email]
                                request.nonce = sha256(nonce)
                            },
                            onCompletion: { result in
                                handleSignInWithApple(result: result)
                            }
                        )
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(12)

                        // 分割线
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)

                            Text("或")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .padding(.horizontal, 12)

                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 8)

                        // 邮箱登录按钮
                        Button(action: {
                            showEmailLogin = true
                        }) {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 18))
                                Text("使用邮箱登录")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .cornerRadius(12)
                        }
                        // 忘记密码
                        Button(action: {
                            showEmailLogin = true
                        }) {
                            Text("忘记密码？")
                                .font(.footnote)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    // 服务条款
                    Text("点击继续即表示您同意我们的\n服务条款和隐私政策")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)
                }
            }

            // 加载指示器
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.black)
                }
            }
        }
        .sheet(isPresented: $showEmailLogin) {
            EmailLoginView()
        }
        .alert("登录失败", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func handleSignInWithApple(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: identityToken, encoding: .utf8) else {
                showError(message: "无法获取登录凭证")
                return
            }

            guard let nonce = currentNonce else {
                showError(message: "登录验证失败，请重试")
                return
            }

            isLoading = true

            Task {
                do {
                    try await authService.signInWithApple(idToken: idTokenString, nonce: nonce)
                    isLoading = false
                } catch {
                    isLoading = false
                    let errorMsg = getDetailedErrorMessage(error)
                    showError(message: errorMsg)
                    print("Apple Sign In Error: \(error)")
                }
            }

        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            let errorMsg = getDetailedErrorMessage(error)
            showError(message: errorMsg)
            print("Apple Sign In Authorization Error: \(error)")
        }
    }

    private func getDetailedErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "无网络连接，请检查网络设置"
            case .timedOut:
                return "连接超时，请重试"
            default:
                return "网络错误：\(urlError.localizedDescription)"
            }
        }

        // Supabase 错误
        if error.localizedDescription.contains("Invalid") {
            return "登录验证失败，请重试"
        }

        return error.localizedDescription
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

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

// MARK: - 邮箱登录视图

struct EmailLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var resetSent = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer()
                            .frame(height: 40)

                        // 标题
                        Text(isSignUp ? "创建账号" : "登录")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.black)

                        VStack(spacing: 16) {
                            // 邮箱输入框
                            VStack(alignment: .leading, spacing: 8) {
                                Text("邮箱")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)

                                TextField("输入邮箱地址", text: $email)
                                    .textFieldStyle(.plain)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                            }

                            // 密码输入框
                            VStack(alignment: .leading, spacing: 8) {
                                Text("密码")
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)

                                SecureField("输入密码", text: $password)
                                    .textFieldStyle(.plain)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                            }

                            // 登录/注册按钮
                            Button(action: {
                                handleEmailAuth()
                            }) {
                                Text(isSignUp ? "注册" : "登录")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        email.isEmpty || password.isEmpty ?
                                        Color.gray : Color.black
                                    )
                                    .cornerRadius(12)
                            }
                            .disabled(email.isEmpty || password.isEmpty)
                            .padding(.top, 8)

                            // 忘记密码
                            if !isSignUp {
                                Button(action: { Task { await sendReset() } }) {
                                    Text("忘记密码？发送重置邮件")
                                        .font(.footnote)
                                        .foregroundStyle(.black)
                                }
                                .padding(.top, 4)
                            }

                            // 切换登录/注册
                            Button(action: {
                                isSignUp.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Text(isSignUp ? "已有账号？" : "还没有账号？")
                                        .foregroundStyle(.gray)
                                    Text(isSignUp ? "登录" : "注册")
                                        .foregroundStyle(.black)
                                        .fontWeight(.semibold)
                                }
                                .font(.subheadline)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 32)

                        Spacer()
                    }
                }

                // 加载指示器
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.black)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.black)
                    }
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("已发送", isPresented: $resetSent) {
            Button("好的", role: .cancel) { }
        } message: {
            Text("重置密码链接已发送至邮箱")
        }
    }

    private func handleEmailAuth() {
        // 验证邮箱格式
        guard isValidEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            showError = true
            return
        }

        // 验证密码长度
        guard password.count >= 6 else {
            errorMessage = "密码至少需要6个字符"
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                if isSignUp {
                    try await authService.signUpWithEmail(email: email, password: password)
                } else {
                    try await authService.signInWithEmail(email: email, password: password)
                }
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = getDetailedEmailErrorMessage(error)
                showError = true
                print("Email Auth Error: \(error)")
            }
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func getDetailedEmailErrorMessage(_ error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()

        if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "网络连接失败，请检查网络设置"
        }

        if errorDescription.contains("invalid") && errorDescription.contains("password") {
            return "密码错误，请重试"
        }

        if errorDescription.contains("invalid") && errorDescription.contains("email") {
            return "邮箱格式不正确"
        }

        if errorDescription.contains("user") && errorDescription.contains("not found") {
            return "该邮箱尚未注册"
        }

        if errorDescription.contains("already") && errorDescription.contains("exists") {
            return "该邮箱已被注册"
        }

        if errorDescription.contains("weak") && errorDescription.contains("password") {
            return "密码强度不够，请使用至少6个字符"
        }

        return error.localizedDescription
    }

    private func sendReset() async {
        guard isValidEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            showError = true
            return
        }
        do {
            // 可按需替换为你的自定义重定向URL
            try await authService.sendPasswordReset(email: email, redirectTo: nil)
            resetSent = true
        } catch {
            errorMessage = getDetailedEmailErrorMessage(error)
            showError = true
        }
    }
}

#Preview {
    LoginView()
}
