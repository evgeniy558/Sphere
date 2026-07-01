import SwiftUI

/// Log in / Sign up sheet content (second step after Welcome "Get started").
/// Designed as a custom dark-glass bottom sheet (presented from `WelcomeView`).
struct AuthSheetView: View {
    let isEnglish: Bool
    let accent: Color
    var startInSignup: Bool = false
    var onAuthenticated: () -> Void
    var onDismiss: () -> Void

    @StateObject private var authService = AuthService.shared

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var rememberMe = true
    @State private var isPasswordVisible = false
    @State private var hasAttemptedSubmit = false
    @State private var isSigningInWithEmail = false
    @State private var isSigningInWithGoogle = false
    @State private var isSendingSignupCode = false
    @State private var signupMessage: String?
    @State private var showVerifyCode = false
    @State private var showTwoFactorSheet = false
    @State private var twoFAChallengeId: String?
    @State private var twoFAMethods: [String] = []
    @State private var twoFAMethod = "email"
    @State private var twoFACode = ""
    @State private var showForgotPassword = false
    @State private var showQRLogin = false

    private enum AuthMode: Hashable {
        case login
        case signup
    }

    private var signInButtonTitle: String { isEnglish ? "Log in" : "Войти" }
    private var signUpButtonTitle: String { isEnglish ? "Sign up" : "Создать аккаунт" }
    private var emailPlaceholder: String { isEnglish ? "Email" : "Почта" }
    private var passwordPlaceholder: String { isEnglish ? "Password" : "Пароль" }
    private var nicknamePlaceholder: String { isEnglish ? "Nickname" : "Никнейм" }
    private var orLabel: String { isEnglish ? "Or" : "Или" }
    private var googleTitle: String { isEnglish ? "Continue with Google" : "Продолжить с Google" }
    private var rememberTitle: String { isEnglish ? "Remember me" : "Запомнить меня" }
    private var forgotTitle: String { isEnglish ? "Forgot password?" : "Забыли пароль?" }
    private var title: String { isEnglish ? "Get Started now" : "Начни сейчас" }
    private var subtitle: String {
        isEnglish
            ? "Create an account or log in to explore Node!"
            : "Создай аккаунт или войди, чтобы исследовать Node!"
    }

    private var formIsValidLogin: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var passwordStrength: SpherePasswordStrength { SpherePasswordStrength.evaluate(password) }

    private var formIsValidSignup: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
            && passwordStrength.isAcceptableForRegister
    }

    private let rememberEmailKey = "welcomeAuthRememberedEmail"
    private static let preferTestAccountKey = "spherePreferTestAccount"
    private let primaryBlueGradient = LinearGradient(
        colors: [
            Color(red: 52 / 255, green: 130 / 255, blue: 1),
            Color(red: 0 / 255, green: 102 / 255, blue: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        ZStack(alignment: .top) {
            // Premium animated background
            NodeHarmonyBackground(isDarkMode: true, accent: accent, intensity: 0.55)
                .ignoresSafeArea()

            // Tall dark glass card that fills almost the entire screen.
            darkGlassCard
                .padding(.horizontal, 12)
                .padding(.top, 36)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .preferredColorScheme(.dark)
        .onAppear {
            mode = startInSignup ? .signup : .login
            if let saved = UserDefaults.standard.string(forKey: rememberEmailKey), !saved.isEmpty {
                email = saved
            } else if UserDefaults.standard.bool(forKey: Self.preferTestAccountKey) {
                email = SphereTestAccount.email
            }
        }
        .fullScreenCover(isPresented: $showVerifyCode) {
            VerifyEmailCodeView(
                isEnglish: isEnglish,
                isDarkMode: true,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                avatarColorIndex: 0,
                customAvatarImage: nil,
                onDone: {
                    showVerifyCode = false
                    if authService.isSignedIn { onAuthenticated() }
                },
                onCancel: { showVerifyCode = false }
            )
        }
        .sheet(isPresented: $showTwoFactorSheet) {
            Group {
                if #available(iOS 16.4, *) {
                    twoFactorSheet
                        .presentationBackground(.thinMaterial)
                } else {
                    twoFactorSheet
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showForgotPassword) {
            Group {
                if #available(iOS 16.4, *) {
                    ForgotPasswordSheetContent(
                        isEnglish: isEnglish,
                        accent: accent,
                        onDismiss: { showForgotPassword = false }
                    )
                    .presentationDetents([.fraction(0.42)])
                    .presentationBackground(.thinMaterial)
                } else {
                    ForgotPasswordSheetContent(
                        isEnglish: isEnglish,
                        accent: accent,
                        onDismiss: { showForgotPassword = false }
                    )
                    .presentationDetents([.fraction(0.42)])
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showQRLogin) {
            QRLoginSignInSheet(
                isEnglish: isEnglish,
                accent: accent,
                onAuthenticated: {
                    showQRLogin = false
                    onAuthenticated()
                },
                onDismiss: { showQRLogin = false }
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Dark glass card

    private var darkGlassCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    segmentedSwitcher
                        .padding(.horizontal, 20).padding(.top, 2)

                    if let err = authService.authError, !err.isEmpty {
                        Text(err).font(.caption).foregroundStyle(Color.red.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    }

                    formFields.padding(.horizontal, 20)
                    submitButton.padding(.horizontal, 20).padding(.top, 6)
                    orDivider.padding(.horizontal, 20).padding(.vertical, 2)
                    googleButton.padding(.horizontal, 20)
                    qrSignInButton.padding(.horizontal, 20)

                    if mode == .login, SphereTestAccount.isConfigured {
                        testAccountButton.padding(.horizontal, 20)
                    }

                    if let signupMessage {
                        Text(signupMessage).font(.caption).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24)
                    }

                    Color.clear.frame(height: 32)
                }.padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(0.65))
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(
                    LinearGradient(colors: [accent.opacity(0.06), .clear, .clear], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            }
        )
        .overlay(alignment: .top) {
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
        }
    }

    // MARK: - Segmented switcher

    private var segmentedSwitcher: some View {
        HStack(spacing: 0) {
            segmentButton(title: isEnglish ? "Log In" : "Вход", isSelected: mode == .login) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { mode = .login }
            }
            segmentButton(title: isEnglish ? "Sign Up" : "Регистрация", isSelected: mode == .signup) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { mode = .signup }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.18) : Color.clear,
                            lineWidth: 0.8
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }

    // MARK: - Fields

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 14) {
            labeledField(title: isEnglish ? "Email/username" : "Почта/логин") {
                DarkGlassTextField(
                    text: $email,
                    placeholder: emailPlaceholder,
                    leadingSystemImage: "envelope"
                ) {
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
            }

            if mode == .signup {
                labeledField(title: isEnglish ? "Nickname" : "Никнейм") {
                    DarkGlassTextField(
                        text: $nickname,
                        placeholder: nicknamePlaceholder,
                        leadingSystemImage: "person"
                    ) {
                        TextField("", text: $nickname)
                            .textContentType(.nickname)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                    }
                }
            }

            labeledField(title: isEnglish ? "Password" : "Пароль") {
                DarkGlassTextField(
                    text: $password,
                    placeholder: passwordPlaceholder,
                    leadingSystemImage: "lock",
                    trailing: {
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                    }
                ) {
                    Group {
                        if isPasswordVisible {
                            TextField("", text: $password)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .textContentType(mode == .login ? .password : .newPassword)
                    .foregroundStyle(.white)
                }
            }

            if mode == .signup, (hasAttemptedSubmit || !password.isEmpty) {
                Text(passwordStrengthSummary(passwordStrength))
                    .font(.caption)
                    .foregroundStyle(passwordStrength.isAcceptableForRegister ? Color.white.opacity(0.7) : Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if mode == .login {
                HStack {
                    Button {
                        rememberMe.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18))
                                .foregroundStyle(rememberMe ? accent : Color.white.opacity(0.5))
                            Text(rememberTitle)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(forgotTitle) {
                        showForgotPassword = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 70 / 255, green: 145 / 255, blue: 1))
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Buttons

    private var submitButton: some View {
        Button(action: submitPrimary) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                }
                Text(mode == .login ? signInButtonTitle : signUpButtonTitle)
                    .font(.system(size: 17, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accent.opacity(0.9), accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    // Subtle shimmer overlay
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.15), .clear, .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .shadow(color: accent.opacity(0.4), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.7 : 1)
        .scaleEffect(isBusy ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isBusy)
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
            Text(orLabel)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.55))
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
        }
    }

    private var googleButton: some View {
        Button(action: signInGoogle) {
            HStack(spacing: 12) {
                if isSigningInWithGoogle {
                    ProgressView().tint(.white)
                } else {
                    Image("google").renderingMode(.original).resizable().scaledToFit().frame(width: 20, height: 20)
                }
                Text(googleTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSigningInWithGoogle)
    }

    private var testAccountButton: some View {
        Button(action: signInAsTestAccount) {
            HStack(spacing: 12) {
                if isSigningInWithEmail {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
                Text(isEnglish ? "Test account (Kirby)" : "Тестовый аккаунт (Kirby)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.green.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var qrSignInButton: some View {
        Button { showQRLogin = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(isEnglish ? "Sign in with QR" : "Войти по QR-коду")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2FA sheet content

    @ViewBuilder
    private var twoFactorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    if twoFAMethods.count > 1 {
                        Picker("", selection: $twoFAMethod) {
                            Text(isEnglish ? "Email" : "Почта").tag("email")
                            Text(isEnglish ? "Authenticator" : "Приложение").tag("totp")
                        }
                        .pickerStyle(.segmented)
                    }
                    SecureField(isEnglish ? "Code" : "Код", text: $twoFACode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    if let err = authService.authError, !err.isEmpty {
                        Text(err)
                            .foregroundStyle(Color.red)
                            .font(.caption)
                    }
                }
                Section {
                    Button(isEnglish ? "Continue" : "Продолжить") {
                        Task { @MainActor in
                            guard let cid = twoFAChallengeId else { return }
                            let ok = await authService.completeBackendTwoFactor(
                                challengeId: cid,
                                method: twoFAMethod,
                                code: twoFACode,
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                password: password
                            )
                            if ok {
                                showTwoFactorSheet = false
                                persistRememberedEmail()
                                onAuthenticated()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(isEnglish ? "Two-factor" : "Двухфакторный вход")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEnglish ? "Cancel" : "Отмена") {
                        showTwoFactorSheet = false
                    }
                }
            }
        }
    }

    private var isBusy: Bool { isSigningInWithEmail || isSendingSignupCode }

    private func persistRememberedEmail() {
        if rememberMe {
            UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: rememberEmailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: rememberEmailKey)
        }
    }

    private func signInAsTestAccount() {
        mode = .login
        email = SphereTestAccount.email
        password = SphereTestAccount.password
        rememberMe = true
        UserDefaults.standard.set(true, forKey: Self.preferTestAccountKey)
        UserDefaults.standard.set(SphereTestAccount.email, forKey: rememberEmailKey)
        submitPrimary()
    }

    private func submitPrimary() {
        signupMessage = nil
        switch mode {
        case .login:
            guard formIsValidLogin else {
                hasAttemptedSubmit = true
                return
            }
            Task { @MainActor in
                isSigningInWithEmail = true
                authService.authError = nil
                let result = await authService.signInWithBackendEmailPassword(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                isSigningInWithEmail = false
                switch result {
                case .success:
                    persistRememberedEmail()
                    onAuthenticated()
                case .needsTwoFactor(let cid, let methods):
                    twoFAChallengeId = cid
                    twoFAMethods = methods
                    twoFAMethod = methods.contains("email") ? "email" : (methods.first ?? "totp")
                    twoFACode = ""
                    showTwoFactorSheet = true
                case .failure:
                    break
                }
            }
        case .signup:
            guard formIsValidSignup else {
                hasAttemptedSubmit = true
                return
            }
            Task {
                await sendSignupCode()
            }
        }
    }

    private func sendSignupCode() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.contains("@") else {
            await MainActor.run {
                signupMessage = isEnglish ? "Enter a valid email" : "Введите корректную почту"
            }
            return
        }
        guard passwordStrength.isAcceptableForRegister else {
            await MainActor.run {
                signupMessage = isEnglish ? "Password is too weak" : "Слишком слабый пароль"
            }
            return
        }
        await MainActor.run {
            isSendingSignupCode = true
            signupMessage = nil
        }
        defer { Task { @MainActor in isSendingSignupCode = false } }
        do {
            try await SphereAPIClient.shared.sendSignupCode(email: e)
            await MainActor.run { showVerifyCode = true }
        } catch {
            await MainActor.run { signupMessage = error.localizedDescription }
        }
    }

    private func signInGoogle() {
        Task {
            isSigningInWithGoogle = true
            await authService.signInWithGoogle()
            isSigningInWithGoogle = false
            if authService.isSignedIn {
                persistRememberedEmail()
                onAuthenticated()
            }
        }
    }

    private func passwordStrengthSummary(_ s: SpherePasswordStrength) -> String {
        let label: String
        switch s.labelKey {
        case "strong": label = isEnglish ? "Strong" : "Сильный"
        case "good": label = isEnglish ? "Good" : "Хороший"
        case "fair": label = isEnglish ? "Medium" : "Средний"
        default: label = isEnglish ? "Weak" : "Слабый"
        }
        return isEnglish
            ? "Strength: \(label) · \(s.score)/100"
            : "Сложность: \(label) · \(s.score)/100"
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
            content()
        }
    }
}

// MARK: - Dark glass field

private struct DarkGlassTextField<Content: View, Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    let leadingSystemImage: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder var field: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: leadingSystemImage)
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 20)
            ZStack(alignment: .leading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                field()
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private extension DarkGlassTextField where Trailing == EmptyView {
    init(
        text: Binding<String>,
        placeholder: String,
        leadingSystemImage: String,
        @ViewBuilder field: @escaping () -> Content
    ) {
        self._text = text
        self.placeholder = placeholder
        self.leadingSystemImage = leadingSystemImage
        self.trailing = { EmptyView() }
        self.field = field
    }
}

// MARK: - QR sign-in sheet

/// Shown from the login screen. Generates a `/auth/qr/start` session, displays the
/// QR code, and long-polls `/auth/qr/poll` for approval from another logged-in
/// device (which scans the QR via Privacy → "Approve QR login").
struct QRLoginSignInSheet: View {
    let isEnglish: Bool
    let accent: Color
    var onAuthenticated: () -> Void
    var onDismiss: () -> Void

    @StateObject private var authService = AuthService.shared

    @State private var qrPayload: String?
    @State private var sessionId: String?
    @State private var statusMessage: String?
    @State private var isStarting = false
    @State private var isExpired = false
    @State private var pollTask: Task<Void, Never>?

    private var titleText: String { isEnglish ? "Sign in with QR" : "Вход по QR-коду" }
    private var instructionsText: String {
        isEnglish
            ? "Open Node on a logged-in device → Settings → Privacy → \"Approve QR login\" and scan this code."
            : "Откройте Node на устройстве, где вы уже вошли → Настройки → Конфиденциальность → «Подтвердить вход по QR» и отсканируйте этот код."
    }
    private var refreshTitle: String { isEnglish ? "New QR" : "Новый QR" }
    private var waitingText: String {
        isEnglish ? "Waiting for approval…" : "Ожидаем подтверждение…"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.07, blue: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Text(instructionsText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    qrCodeBox

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(isExpired ? Color.red.opacity(0.9) : Color.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                    } else if qrPayload != nil {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(waitingText)
                                .font(.footnote)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }

                    if isExpired || (qrPayload == nil && !isStarting) {
                        Button(refreshTitle) {
                            Task { await startSession() }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent.opacity(0.85))
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 14)
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEnglish ? "Close" : "Закрыть") {
                        pollTask?.cancel()
                        onDismiss()
                    }
                    .tint(.white)
                }
            }
        }
        .task {
            await startSession()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private var qrCodeBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .frame(width: 280, height: 280)
                .shadow(color: Color.black.opacity(0.4), radius: 18, x: 0, y: 10)
            if let payload = qrPayload {
                SphereQRLoginQRImage(payload: payload)
                    .opacity(isExpired ? 0.25 : 1.0)
            } else if isStarting {
                ProgressView().tint(.black)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 64))
                    .foregroundStyle(.black.opacity(0.5))
            }
        }
    }

    private func startSession() async {
        await MainActor.run {
            isStarting = true
            isExpired = false
            statusMessage = nil
            qrPayload = nil
            sessionId = nil
        }
        defer {
            Task { @MainActor in isStarting = false }
        }
        do {
            let resp = try await SphereAPIClient.shared.qrLoginStart()
            await MainActor.run {
                qrPayload = resp.qrPayload
                sessionId = resp.sessionId
            }
            startPolling(sessionId: resp.sessionId)
        } catch {
            await MainActor.run {
                statusMessage = isEnglish
                    ? "Could not start QR session: \(error.localizedDescription)"
                    : "Не удалось создать QR: \(error.localizedDescription)"
            }
        }
    }

    private func startPolling(sessionId: String) {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            // Each `qrLoginPollOnce` long-polls up to ~55s. Loop until approved,
            // gone (expired/cancelled), or the user dismisses the sheet.
            while !Task.isCancelled {
                do {
                    let result = try await SphereAPIClient.shared.qrLoginPollOnce(sessionId: sessionId)
                    if Task.isCancelled { return }
                    switch result {
                    case .approved(let auth):
                        // qrLoginPollOnce already persisted the JWT inside SphereAPIClient.
                        // Just fan the backend user into the local profile.
                        authService.applyBackendUser(auth.user)
                        Task { await authService.refreshBackendAccountFromServer() }
                        statusMessage = isEnglish ? "Signed in" : "Вход выполнен"
                        onAuthenticated()
                        return
                    case .pending:
                        continue
                    case .gone:
                        isExpired = true
                        statusMessage = isEnglish
                            ? "QR expired — tap \"New QR\" to try again."
                            : "QR-код истёк — нажмите «Новый QR»."
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    statusMessage = error.localizedDescription
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
}
