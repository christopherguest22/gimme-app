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
        ("location.north.circle.fill", "Every yard, every hole", "GPS distances to the front, middle and back of the green, hazards and carries."),
        ("person.3.fill", "Play with your crew", "A live scorecard, skins and Nassau, and a chat for your group while you play."),
        ("gift.fill", "Win gear on the course", "Golf brands drop prizes on holes. Reach the green and it's yours."),
    ]

    var body: some View {
        ZStack {
            LinearGradient.gimmeFairway.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Gimme")
                    .font(.gimme(44, .heavy))
                    .foregroundStyle(.white)
                    .padding(.top, 40)

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

    private var slidesView: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        Image(systemName: slides[i].icon)
                            .font(.system(size: 84))
                            .foregroundStyle(i == 2 ? Color.gimmeGold : .white)
                        Text(slides[i].title).font(.gimme(28, .bold)).foregroundStyle(.white)
                        Text(slides[i].text)
                            .font(.gimme(17))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
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
