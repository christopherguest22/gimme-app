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
                .task {
                    location.requestPermission()
                    await app.load()
                }
        }
    }
}

extension Color {
    static let gimmeGreen = Color(red: 0.11, green: 0.55, blue: 0.29)
    static let gimmeGold = Color(red: 0.95, green: 0.72, blue: 0.13)
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var tab = Tab.home

    enum Tab { case home, round, friends, wallet, profile }

    var body: some View {
        @Bindable var app = app
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
                .badge(app.wallet.count)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .onChange(of: location.coordinate) { _, point in
            guard let point else { return }
            Task { await app.handleLocation(point) }
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
}
