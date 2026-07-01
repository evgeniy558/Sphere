import Foundation

/// Shared QA account on the production Go backend (no email verification).
enum SphereTestAccount {
    static let email = "kirby.test@sphere.app"
    static let password = "sphere_kirby_test_autopass"
    static let displayName = "Kirby Test"

    static var isConfigured: Bool {
        !email.isEmpty && !password.isEmpty
    }
}
