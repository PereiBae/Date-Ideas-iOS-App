import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum Theme {
    static let accent = Color.indigo

    // Reserved exclusively for Apple Intelligence provenance UI.
    static let aiGradient = LinearGradient(
        colors: [.indigo, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func configureNavigationTitleFonts() {
        guard let descriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif)?
            .withSymbolicTraits(.traitBold) else { return }

        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(descriptor: descriptor, size: 0)
        ]
    }
}

extension Font {
    static func placeTitle(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}

@main
struct DateIdeasApp: App {
    @StateObject private var store = DateIdeaStore()
    @StateObject private var collaborationStore = CollaborationStore()

    init() {
        Theme.configureNavigationTitleFonts()
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if collaborationStore.currentUser == nil {
                    AuthenticationGateView()
                } else {
                    RootView()
                }
            }
            .tint(Theme.accent)
            .environmentObject(store)
            .environmentObject(collaborationStore)
            .onAppear {
                collaborationStore.attach(dateIdeaStore: store)
            }
        }
    }
}
