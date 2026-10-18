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
                .tint(.gimmeGreen)
                .fontDesign(.rounded)
                .task {
                    location.requestPermission()
                    await app.load()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var tab = Tab.home

    enum Tab { case home, round, friends, wallet, profile }

    var body: some View {
        @Bindable var app = app
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
        .sheet(item: $app.justWon) { prize in
            DropFoundView(prize: prize)
        }
        .alert("Gimme", isPresented: Binding(get: { app.message != nil }, set: { if !$0 { app.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.message ?? "")
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(startRound: { tab = .round })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            RoundView()
                .tabItem { Label("Round", systemImage: "flag.fill") }
                .tag(Tab.round)
            FeedView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .tag(Tab.friends)
            WalletView()
                .tabItem { Label("Prizes", systemImage: "gift.fill") }
                .tag(Tab.wallet)
                .badge(app.wallet.filter { !$0.redeemed }.count)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
    }
}
