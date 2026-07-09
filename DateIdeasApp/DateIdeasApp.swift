import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum Theme {
    // Rosé — deep enough for WCAG AA white text on filled chips and buttons.
    static let accent = Color(red: 199 / 255, green: 64 / 255, blue: 105 / 255)

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

// Lets bottom-pinned bars hide while the keyboard is up instead of
// floating above it (where they collide with the keyboard Done button).
private struct KeyboardVisibilityObserver: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.smooth(duration: 0.2)) {
                    isVisible = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.smooth(duration: 0.2)) {
                    isVisible = false
                }
            }
    }
}

extension View {
    func observesKeyboardVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(KeyboardVisibilityObserver(isVisible: isVisible))
    }

    // Swipe-to-dismiss plus a Done button above the keyboard, for forms.
    func keyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
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
            .onOpenURL { url in
#if canImport(GoogleSignIn)
                GIDSignIn.sharedInstance.handle(url)
#endif
            }
        }
    }
}
