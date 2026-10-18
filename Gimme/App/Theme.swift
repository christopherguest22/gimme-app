import SwiftUI

/// Gimme's look: fairway greens, a gold "prize" accent, rounded type and soft cards.
extension Color {
    static let gimmeGreen = Color(red: 0.11, green: 0.55, blue: 0.29)
    static let gimmeDeepGreen = Color(red: 0.04, green: 0.29, blue: 0.16)
    static let gimmeGold = Color(red: 0.95, green: 0.72, blue: 0.13)
    static let gimmeSand = Color(red: 0.93, green: 0.85, blue: 0.62)
    static let gimmeBirdie = Color(red: 0.86, green: 0.20, blue: 0.20)
    static let gimmeBogey = Color(red: 0.20, green: 0.42, blue: 0.85)

    // Dark, map-first surfaces (the app runs in dark mode like most golf GPS apps).
    static let gimmeBackground = Color(red: 0.04, green: 0.08, blue: 0.06)
    static let gimmeSurface = Color(red: 0.08, green: 0.13, blue: 0.10)
    static let gimmeSurfaceRaised = Color(red: 0.12, green: 0.18, blue: 0.14)
    /// Brighter green that reads well on the dark surfaces.
    static let gimmeLime = Color(red: 0.18, green: 0.75, blue: 0.42)
}

extension LinearGradient {
    static let gimmeFairway = LinearGradient(colors: [.gimmeDeepGreen, .gimmeGreen],
                                             startPoint: .top, endPoint: .bottom)
    static let gimmePrize = LinearGradient(colors: [.gimmeGold, Color(red: 1, green: 0.85, blue: 0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Font {
    static func gimme(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct GimmeCard: ViewModifier {
    var highlight: Color?

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.gimmeSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if let highlight {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(highlight, lineWidth: 2)
                }
            }
    }
}

extension View {
    func gimmeCard(highlight: Color? = nil) -> some View {
        modifier(GimmeCard(highlight: highlight))
    }
}

/// Big pill button used for the main action on a screen.
struct GimmeButtonStyle: ButtonStyle {
    var prize = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gimme(17, .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Color.black)
            .background(prize ? AnyShapeStyle(LinearGradient.gimmePrize) : AnyShapeStyle(Color.gimmeLime),
                        in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GimmeButtonStyle {
    static var gimme: GimmeButtonStyle { GimmeButtonStyle() }
    static var gimmePrize: GimmeButtonStyle { GimmeButtonStyle(prize: true) }
}

/// Small rounded avatar bubble for a player's emoji.
struct AvatarView: View {
    let player: Player
    var size: CGFloat = 40

    var body: some View {
        Text(player.avatar)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Color.gimmeSurfaceRaised, in: Circle())
    }
}

/// Section header in the dark style: small caps label with an optional action.
struct SectionHeader: View {
    let title: String
    var action: (label: String, run: () -> Void)?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.gimme(13, .heavy))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button(action.label, action: action.run)
                    .font(.gimme(14, .bold))
                    .foregroundStyle(Color.gimmeLime)
            }
        }
        .padding(.top, 6)
    }
}
