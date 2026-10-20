import SwiftUI

/// Welcome slides, then sign-in: an emailed 6-digit code with Supabase, or a name and avatar in the demo.
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var page = 0
    @State private var step = Step.slides
    @State private var email = ""
    @State private var code = ""
    @State private var name = ""
    @State private var avatar = "🏌️"
    @State private var working = false

    enum Step { case slides, email, code, profile }

    private let slides: [(icon: String, title: String, text: String)] = [
        ("gift.fill", "Win gear on the course", "Brands drop prizes on the course. Walk into the drop zone during your round and it's yours."),
        ("location.north.circle.fill", "Every yard, every hole", "GPS distances to the front, middle and back of the green, hazards and carries."),
        ("person.3.fill", "Play with your crew", "A live scorecard, skins and Nassau, and a chat for your group while you play."),
    ]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 24) {
                Text("Gimme")
                    .font(.gimme(44, .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                    .padding(.top, 16)

                switch step {
                case .slides: slidesView
                case .email: emailView
                case .code: codeView
                case .profile: profileView
                }
            }
            .padding(24)
        }
        .animation(.easeInOut, value: step)
    }

    /// The putt photo with a prize-drop pin on the green, darkened at the top and bottom so the text reads, and all over once
    /// the golfer is typing.
    private var background: some View {
        GeometryReader { geo in
            Image("WelcomeHero")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .shade.opacity(0.82), location: 0),
                        .init(color: .shade.opacity(0.55), location: 0.22),
                        .init(color: .clear, location: 0.38),
                        .init(color: .clear, location: 0.8),
                        .init(color: .shade.opacity(0.75), location: 0.9),
                        .init(color: .shade.opacity(0.92), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .overlay { Color.shade.opacity(step == .slides ? 0 : 0.55) }
        }
        .ignoresSafeArea()
        .accessibilityLabel("A golfer celebrates his putt while a gold map pin marks a prize drop on the green")
    }

    private var slidesView: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    // The photo is the hero, so the slide text sits up top, under the logo.
                    VStack(spacing: 6) {
                        Text(slides[i].title).font(.gimme(25, .heavy)).foregroundStyle(.white)
                        Text(slides[i].text)
                            .font(.gimme(15, .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                    .padding(.top, -12)
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            Button {
                if page < slides.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    step = app.isDemo ? .profile : .email
                }
            } label: {
                Text(page < slides.count - 1 ? "Next" : "Get started")
            }
            .buttonStyle(.gimmePrize)
        }
    }

    private var emailView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Sign in with your email").font(.gimme(22, .bold)).foregroundStyle(.white)
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            Button {
                Task {
                    working = true
                    if await app.sendCode(to: email) { step = .code }
                    working = false
                }
            } label: {
                if working { ProgressView() } else { Text("Email me a code") }
            }
            .buttonStyle(.gimmePrize)
            .disabled(!email.contains("@") || working)
            Spacer()
        }
    }

    private var codeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Enter the 6-digit code we sent to \(email)")
                .font(.gimme(20, .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            TextField("123456", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.gimme(28, .bold))
                .multilineTextAlignment(.center)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            Button {
                Task {
                    working = true
                    await app.verify(email: email, code: code)
                    working = false
                }
            } label: {
                if working { ProgressView() } else { Text("Sign in") }
            }
            .buttonStyle(.gimmePrize)
            .disabled(code.count < 6 || working)
            Button("Use a different email") { step = .email }
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var profileView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("What should your buddies call you?").font(.gimme(22, .bold)).foregroundStyle(.white)
            TextField("Your name", text: $name)
                .padding()
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            AvatarPicker(selection: $avatar)
            Button("Tee it up") {
                Task { await app.updateProfile(name: name, avatar: avatar) }
            }
            .buttonStyle(.gimmePrize)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Demo mode: sample friends and prizes, nothing leaves your phone.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
    }
}

private extension Color {
    /// Deep green-black used to darken the welcome photo.
    static let shade = Color(red: 0.02, green: 0.09, blue: 0.05)
}

struct AvatarPicker: View {
    @Binding var selection: String
    static let options = ["🏌️", "🏌️‍♀️", "⛳️", "🦅", "🐯", "🧢", "🍺", "🔥", "🐐", "🦈"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.options, id: \.self) { option in
                    Text(option)
                        .font(.system(size: 30))
                        .frame(width: 52, height: 52)
                        .background(selection == option ? Color.gimmeGold : Color.white.opacity(0.2), in: Circle())
                        .onTapGesture { selection = option }
                }
            }
        }
    }
}
