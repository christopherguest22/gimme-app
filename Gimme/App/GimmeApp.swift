import SwiftUI

@main
struct GimmeApp: App {
    @State private var app = AppState()
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(location)
                .tint(.gimmeLime)
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
                .task {
                    location.requestPermission()
                    await app.load()
                }
        }
    }
}

enum GimmeTab: CaseIterable {
    case home, community, prizes, me

    var title: String {
        switch self {
        case .home: "Home"
        case .community: "Community"
        case .prizes: "Prizes"
        case .me: "Me"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .community: "person.3.fill"
        case .prizes: "gift.fill"
        case .me: "person.crop.circle.fill"
        }
    }
}

/// Four tabs around a raised center Play button. Play starts a round, or reopens the one
/// in progress full screen, the way golf GPS apps keep the course map out of the tab bar.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var tab = GimmeTab.home
    @State private var showingRound = false
    @State private var choosingCourse = false

    var body: some View {
        Group {
            if app.isLoading {
                ZStack {
                    LinearGradient.gimmeFairway.ignoresSafeArea()
                    Text("Gimme").font(.gimme(44, .heavy)).foregroundStyle(.white)
                }
            } else if app.me == nil {
                OnboardingView()
            } else {
                tabs
            }
        }
        .onChange(of: location.coordinate) { _, point in
            guard let point else { return }
            Task { await app.handleLocation(point) }
        }
        .onChange(of: app.round == nil) { _, ended in
            // Keep GPS running in the background only while a round is on.
            if ended { location.stopRound() } else { location.startRound() }
        }
        .appMessages(active: !showingRound)
    }

    private var tabs: some View {
        Group {
            switch tab {
            case .home: HomeView(startRound: openPlay)
            case .community: CommunityView()
            case .prizes: WalletView()
            case .me: ProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gimmeBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GimmeTabBar(selection: $tab,
                        roundActive: app.round != nil,
                        prizeBadge: app.wallet.filter { !$0.redeemed }.count,
                        onPlay: openPlay)
        }
        .sheet(isPresented: $choosingCourse) {
            StartRoundView {
                // Let the sheet finish closing before the round covers the screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showingRound = true }
            }
        }
        .fullScreenCover(isPresented: $showingRound) {
            RoundView()
        }
    }

    private func openPlay() {
        if app.round != nil { showingRound = true } else { choosingCourse = true }
    }
}

struct GimmeTabBar: View {
    @Binding var selection: GimmeTab
    var roundActive: Bool
    var prizeBadge: Int
    var onPlay: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.home)
            item(.community)
            Button(action: onPlay) {
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(roundActive ? AnyShapeStyle(LinearGradient.gimmePrize) : AnyShapeStyle(Color.gimmeLime))
                            .frame(width: 62, height: 62)
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                        Image(systemName: roundActive ? "location.north.line.fill" : "flag.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .offset(y: -14)
                    .padding(.bottom, -14)
                    Text(roundActive ? "Resume" : "Play")
                        .font(.gimme(11, .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel(roundActive ? "Resume round" : "Play a round")
            item(.prizes, badge: prizeBadge)
            item(.me)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Color.gimmeSurface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }

    private func item(_ tab: GimmeTab, badge: Int = 0) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.gimmeGold, in: Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(tab.title).font(.gimme(11, .bold))
            }
            .foregroundStyle(selection == tab ? Color.gimmeLime : Color.white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

/// The prize sheet and app alerts. Attached at the root and inside the full-screen round,
/// with `active` set so only the visible one presents.
struct AppMessages: ViewModifier {
    @Environment(AppState.self) private var app
    var active: Bool

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .sheet(item: active ? $app.justWon : .constant(nil)) { prize in
                DropFoundView(prize: prize)
            }
            .alert("Gimme", isPresented: Binding(get: { active && app.message != nil },
                                                 set: { if !$0 { app.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.message ?? "")
            }
    }
}

extension View {
    func appMessages(active: Bool) -> some View {
        modifier(AppMessages(active: active))
    }
}
