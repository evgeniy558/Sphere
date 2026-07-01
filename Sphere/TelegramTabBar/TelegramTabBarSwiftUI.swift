import SwiftUI
import UIKit

struct TabBarSwiftUI: UIViewRepresentable {
    let homeTitle: String
    let favoritesTitle: String
    let createTitle: String
    let accent: Color
    @Binding var selectedTab: MainAppTab
    var onCreateTap: (() -> Void)?

    private func tabItems() -> [SphereTabBarView.Item] {
        [
            .init(id: MainAppTab.home.rawValue, title: homeTitle, imageName: "Spherelogo"),
            .init(id: MainAppTab.favorites.rawValue, title: favoritesTitle, imageName: "books.vertical.fill"),
            .init(id: MainAppTab.create.rawValue, title: createTitle, imageName: "plus"),
        ]
    }

    func makeUIView(context: Context) -> SphereTabBarView {
        let view = SphereTabBarView()
        view.configure(
            items: tabItems(),
            selectedId: selectedTab.rawValue,
            accentColor: UIColor(accent),
            isDark: UITraitCollection.current.userInterfaceStyle == .dark
        )
        view.onSelect = { id in
            if id == MainAppTab.create.rawValue {
                DispatchQueue.main.async { onCreateTap?() }
                return
            }
            if let tab = MainAppTab(rawValue: id) {
                DispatchQueue.main.async { selectedTab = tab }
            }
        }
        return view
    }

    func updateUIView(_ uiView: SphereTabBarView, context: Context) {
        let displayId: Int = {
            if selectedTab == .create { return MainAppTab.home.rawValue }
            if selectedTab == .profile { return MainAppTab.home.rawValue }
            return selectedTab.rawValue
        }()
        uiView.configure(
            items: tabItems(),
            selectedId: displayId,
            accentColor: UIColor(accent),
            isDark: context.environment.colorScheme == .dark
        )
    }
}
