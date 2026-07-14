import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// Warm editorial design language from the approved RendezQueue mockup:
// cream surfaces, brown text, bold orange accent, pink avatar gradient.
enum Theme {
    static let accent = Color(light: 0xF26B1D, dark: 0xF58A3C)

    // Small tinted tag chips (rounded rects, not capsules).
    static let accentTintBackground = Color(light: 0xFDE9DB, dark: 0x3A2418)
    static let accentTintForeground = Color(light: 0xC0521A, dark: 0xF5A46B)
    static let neutralChipBackground = Color(light: 0xF4EDE7, dark: 0x2E2A26)
    static let neutralChipForeground = Color(light: 0x6E635B, dark: 0xBFB5AA)

    // Page + card surfaces.
    static let background = Color(light: 0xFBF7F3, dark: 0x1C1917)
    static let cardBackground = Color(light: 0xFFFFFF, dark: 0x26211D)
    static let hairline = Color(light: 0x2B2420, dark: 0xFFFFFF).opacity(0.10)

    // Warm paper page gradient (app-level background from the mockup).
    static let paperGradient = LinearGradient(
        colors: [
            Color(light: 0xF5ECE7, dark: 0x201C19),
            Color(light: 0xEADFD9, dark: 0x1B1714),
            Color(light: 0xE4D7CF, dark: 0x161311)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // Warm text ramp.
    static let textPrimary = Color(light: 0x2B2420, dark: 0xF0E7E1)
    static let textSecondary = Color(light: 0x6E635B, dark: 0xA99E93)
    static let textTertiary = Color(light: 0x8A7F76, dark: 0x8A7F76)

    // Warm card shadow — strong enough that cards read as floating.
    static let cardShadow = Color(light: 0x3C281E, dark: 0x000000).opacity(0.28)

    // Status trio (pins, chips, dots).
    static let visited = Color(light: 0x3E8E5A, dark: 0x4FA76C)
    static let endingSoon = Color(light: 0xD8442E, dark: 0xE05A45)

    // Primary call-to-action fill.
    static let accentGradient = LinearGradient(
        colors: [Color(light: 0xF58A3C, dark: 0xF58A3C), Color(light: 0xE8551A, dark: 0xE8551A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Contributor avatars.
    static let avatarGradient = LinearGradient(
        colors: [Color(light: 0xE86FA0, dark: 0xE86FA0), Color(light: 0xC13E76, dark: 0xC13E76)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Reserved exclusively for Apple Intelligence provenance UI.
    static let aiGradient = LinearGradient(
        colors: [.indigo, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func configureNavigationTitleFonts() {
        // Bricolage Grotesque display type on every navigation title.
        if let large = UIFont(name: "BricolageGrotesque-ExtraBold", size: 32) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        }
        if let inline = UIFont(name: "BricolageGrotesque-Bold", size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: inline]
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Font {
    private static func size(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .extraLargeTitle: 36
        case .largeTitle: 34
        case .extraLargeTitle2: 28
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    // Display type (Bricolage Grotesque) for place names and headers.
    static func placeTitle(_ style: Font.TextStyle = .headline) -> Font {
        .custom("BricolageGrotesque-Bold", size: size(of: style), relativeTo: style)
    }

    static func displayHeavy(_ style: Font.TextStyle = .title) -> Font {
        .custom("BricolageGrotesque-ExtraBold", size: size(of: style), relativeTo: style)
    }

    // UI/body type (Hanken Grotesk).
    static func ui(_ style: Font.TextStyle = .body, weight: UIWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size(of: style), relativeTo: style)
    }

    enum UIWeight {
        case regular, medium, semibold, bold

        var postScriptName: String {
            switch self {
            case .regular: "HankenGrotesk-Regular"
            case .medium: "HankenGrotesk-Medium"
            case .semibold: "HankenGrotesk-SemiBold"
            case .bold: "HankenGrotesk-Bold"
            }
        }
    }

    // Mono accents (Space Mono) for tiny labels, codes, timestamps.
    static func mono(_ style: Font.TextStyle = .caption2, bold: Bool = false) -> Font {
        .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size(of: style), relativeTo: style)
    }
}

// Small uppercase mono section labels ("INVITE CODE", "VISITS", ...).
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(.caption2, bold: true))
            .kerning(1.1)
            .foregroundStyle(Theme.textTertiary)
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
    // Warm paper gradient behind lists and forms (mockup design).
    func themedScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paperGradient.ignoresSafeArea())
    }

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
            .font(.ui(.body))
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
