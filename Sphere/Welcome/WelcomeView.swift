import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    let isEnglish: Bool
    let accent: Color
    var onAuthenticated: () -> Void

    @StateObject private var authService = AuthService.shared
    @State private var showAuthSheet = false
    @State private var startAuthSheetInSignup = false

    private var appTitle: String { "Node" }
    private var slogan: String { isEnglish ? "All your music in one place" : "вся ваша музыка в одном месте" }
    private var registrationTitle: String { isEnglish ? "Register with Email" : "Регистрация по почте" }

    var body: some View {
        ZStack {
            WelcomeLoginCoverBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Image("NodeAuthIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 94, height: 94)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )

                    Text(appTitle.uppercased())
                        .font(.nodeMono(size: 22, weight: .heavy))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .padding(.top, 10)

                    Text(slogan)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 24)

                    SignInWithAppleButton(
                        .signUp,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                                    authService.authError = isEnglish ? "Apple authorization failed" : "Ошибка авторизации Apple"
                                    return
                                }
                                Task {
                                    await authService.signInWithApple(credential: credential)
                                    if authService.isSignedIn {
                                        onAuthenticated()
                                    }
                                }
                            case .failure(let error):
                                authService.authError = error.localizedDescription
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                    .padding(.bottom, 12)

                    Button {
                        withAnimation(.spring(response: 0.75, dampingFraction: 0.86)) {
                            startAuthSheetInSignup = true
                            showAuthSheet = true
                        }
                    } label: {
                        Text(registrationTitle)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 29, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 29, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }

                    if let err = authService.authError, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.top, 12)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .opacity(showAuthSheet ? 0 : 1)
                .animation(.easeInOut(duration: 0.35), value: showAuthSheet)
            }

            // Custom dark glass bottom sheet — slower animation, no swipe-to-dismiss.
            if showAuthSheet {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)

                AuthSheetView(
                    isEnglish: isEnglish,
                    accent: accent,
                    startInSignup: startAuthSheetInSignup,
                    onAuthenticated: {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                            showAuthSheet = false
                            startAuthSheetInSignup = false
                        }
                        onAuthenticated()
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) {
                            showAuthSheet = false
                            startAuthSheetInSignup = false
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
    }
}
