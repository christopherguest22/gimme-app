import SwiftUI
import UIKit

/// Community: the feed, a leaderboard of your friends, and your friends list, on one tab.
struct CommunityView: View {
    @Environment(AppState.self) private var app
    @State private var pane = Pane.feed
    @State private var draft = ""
    @State private var addingFriend = false
    @State private var handle = ""

    enum Pane: String, CaseIterable { case feed = "Feed", leaderboard = "Leaderboard", friends = "Friends" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch pane {
                        case .feed: feed
                        case .leaderboard: leaderboard
                        case .friends: friendsList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable { await app.load() }
            }
            .background(Color.gimmeBackground)
            .navigationTitle("Community")
            .toolbarBackground(Color.gimmeBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Add a friend")
                }
            }
            .alert("Add a friend", isPresented: $addingFriend) {
                TextField("Their Gimme handle", text: $handle)
                    .textInputAutocapitalization(.never)
                Button("Add") {
                    let name = handle
                    handle = ""
                    Task { await app.addFriend(name) }
                }
                Button("Cancel", role: .cancel) { handle = "" }
            } message: {
                Text("Your friend's handle is on their Me tab.")
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        HStack(spacing: 10) {
            if let me = app.me { AvatarView(player: me, size: 36) }
            TextField("Share something with your crew", text: $draft)
                .font(.gimme(15))
            Button("Post") {
                let text = draft
                draft = ""
                Task { await app.post(text) }
            }
            .font(.gimme(15, .bold))
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .gimmeCard()

        if app.feed.isEmpty {
            Text("Rounds and prizes from you and your friends show up here.")
                .foregroundStyle(.secondary).padding(.top, 20)
        }
        ForEach(app.feed) { post in
            FeedRow(post: post).gimmeCard(highlight: post.kind == .drop ? Color.gimmeGold : nil)
        }
    }

    /// Friends ranked by handicap, lowest first.
    @ViewBuilder
    private var leaderboard: some View {
        let everyone = rankedPlayers
        SectionHeader(title: "Handicap leaderboard")
        VStack(spacing: 0) {
            ForEach(Array(everyone.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.gimme(16, .heavy))
                        .foregroundStyle(index == 0 ? Color.gimmeGold : .secondary)
                        .frame(width: 26)
                    AvatarView(player: player, size: 36)
                    Text(player.id == app.myId ? "\(player.name) (you)" : player.name).font(.gimme(15, .bold))
                    Spacer()
                    Text(player.handicap.map { String(format: "%.1f", $0) } ?? "–").font(.gimme(18, .heavy))
                }
                .padding(.vertical, 10)
                if index < everyone.count - 1 { Divider() }
            }
        }
        .gimmeCard()
    }

    private var rankedPlayers: [Player] {
        var players = app.friends
        if var you = app.me {
            you.handicap = app.handicapEstimate ?? you.handicap
            players.append(you)
        }
        return players.sorted { ($0.handicap ?? 99) < ($1.handicap ?? 99) }
    }

    @ViewBuilder
    private var friendsList: some View {
        Button { addingFriend = true } label: {
            Label("Add a friend by handle", systemImage: "person.badge.plus")
                .font(.gimme(15, .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gimmeCard()
        ForEach(app.friends) { friend in
            HStack(spacing: 12) {
                AvatarView(player: friend, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name).font(.gimme(16, .bold))
                    Text(friend.playingNow ?? "Handicap \(friend.handicap.map { String(format: "%.1f", $0) } ?? "–")")
                        .font(.gimme(13))
                        .foregroundStyle(friend.playingNow == nil ? Color.secondary : Color.gimmeLime)
                }
                Spacer()
            }
            .gimmeCard()
        }
    }
}

struct FeedRow: View {
    @Environment(AppState.self) private var app
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AvatarView(player: post.author, size: 34)
                Text(post.author.name).font(.subheadline.bold())
                Spacer()
                Text(post.postedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            Label(post.title, systemImage: post.icon)
                .font(.headline)
                .foregroundStyle(post.kind == .drop ? Color.gimmeGold : .primary)
            if !post.detail.isEmpty {
                Text(post.detail).font(.subheadline)
            }
            Button { app.toggleLike(post) } label: {
                Label("\(post.likes)", systemImage: post.likedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct WalletView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.wallet.isEmpty {
                    ContentUnavailableView("No prizes yet",
                                           systemImage: "gift",
                                           description: Text("Play a hole with a gold flag to win gear and discounts from golf brands."))
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(app.wallet) { prize in PrizeCard(prize: prize) }
                        }
                        .padding()
                    }
                    .background(Color.gimmeBackground)
                }
            }
            .navigationTitle("Prize wallet")
        }
    }
}

struct PrizeCard: View {
    let prize: WonPrize
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "gift.fill").foregroundStyle(.black.opacity(0.7))
                Text(prize.drop.brand.uppercased()).font(.caption.bold()).foregroundStyle(.black.opacity(0.7))
                Spacer()
                if prize.redeemed {
                    Text("Redeemed").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.15), in: Capsule())
                }
            }
            Text(prize.drop.prize).font(.gimme(22, .bold)).foregroundStyle(.black)
            Text(prize.drop.detail).font(.subheadline).foregroundStyle(.black.opacity(0.8))
            HStack {
                Text(prize.code)
                    .font(.system(.title3, design: .monospaced).bold())
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = prize.code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.black)
            }
            .padding(10)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            Text("Won on hole \(prize.drop.holeNumber) · expires \(prize.drop.expires.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.black.opacity(0.7))
        }
        .padding(16)
        .background(LinearGradient.gimmePrize, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(prize.redeemed ? 0.6 : 1)
    }
}

/// The unlock moment.
struct DropFoundView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let prize: WonPrize
    @State private var shared = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient.gimmeFairway.ignoresSafeArea()
            Confetti(active: appeared)
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "gift.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(LinearGradient.gimmePrize)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -30))
                Text("You found a drop!").font(.gimme(34, .heavy)).foregroundStyle(.white)
                Text(prize.drop.brand).font(.title3).foregroundStyle(.white.opacity(0.8))
                Text(prize.drop.prize).font(.gimme(26, .bold)).foregroundStyle(Color.gimmeGold).multilineTextAlignment(.center)
                Text(prize.drop.detail).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Only \(prize.drop.remaining) left").font(.caption.bold()).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button {
                    Task {
                        await app.share(prize)
                        shared = true
                    }
                } label: {
                    Text(shared ? "Shared with your crew" : "Share with your crew")
                }
                .buttonStyle(.gimme)
                .disabled(shared)
                Button("Added to your wallet") { dismiss() }
                    .buttonStyle(.gimmePrize)
            }
            .padding(24)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { appeared = true }
        }
    }
}

/// Simple falling-confetti burst for the drop moment.
struct Confetti: View {
    var active: Bool
    private let pieces = (0..<40).map { _ in
        (x: CGFloat.random(in: 0...1), delay: Double.random(in: 0...0.6),
         color: [Color.gimmeGold, .white, .gimmeSand, .orange].randomElement()!, spin: Double.random(in: 180...720))
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces.indices, id: \.self) { i in
                let piece = pieces[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: 8, height: 14)
                    .rotationEffect(.degrees(active ? piece.spin : 0))
                    .position(x: piece.x * geo.size.width, y: active ? geo.size.height + 20 : -20)
                    .animation(.easeIn(duration: 2.2).delay(piece.delay), value: active)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Me: profile header with counts and handicap, your stats, and round history.
struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var editing = false

    private var fullRounds: [Round] { app.pastRounds.filter { $0.holesPlayed(app.myId) == $0.pars.count && $0.pars.count == 18 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    SectionHeader(title: "Stats")
                    HStack(spacing: 10) {
                        statTile(averageScore, "Avg 18")
                        statTile(fullRounds.map { $0.total(app.myId) }.min().map { "\($0)" } ?? "–", "Best 18")
                        statTile("\(birdies)", "Birdies")
                    }
                    SectionHeader(title: "Round history")
                    if app.pastRounds.isEmpty {
                        Text("Finished rounds show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(app.pastRounds) { round in
                        NavigationLink {
                            ScorecardView(round: round)
                                .navigationTitle(round.courseName)
                                .background(Color.gimmeBackground)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(round.courseName).font(.gimme(15, .bold))
                                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.gimme(12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(round.total(app.myId))").font(.gimme(22, .heavy))
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.white)
                            .gimmeCard()
                        }
                    }
                    Text("Handicap is an estimate using the World Handicap System method, not an official handicap index.")
                        .font(.gimme(12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.gimmeBackground)
            .navigationTitle("Me")
            .toolbarBackground(Color.gimmeBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit profile", systemImage: "pencil") { editing = true }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await app.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Profile options")
                }
            }
            .sheet(isPresented: $editing) { EditProfileView() }
        }
    }

    private var averageScore: String {
        guard !fullRounds.isEmpty else { return "–" }
        let total = fullRounds.map { $0.total(app.myId) }.reduce(0, +)
        return String(format: "%.1f", Double(total) / Double(fullRounds.count))
    }

    private var birdies: Int {
        app.pastRounds.reduce(0) { sum, round in
            sum + round.pars.indices.filter { i in (round.strokes(app.myId, hole: i + 1) ?? 99) < round.pars[i] }.count
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                if let me = app.me { AvatarView(player: me, size: 76) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.me?.name ?? "").font(.gimme(26, .heavy))
                    Text("Gimme golfer").font(.gimme(13, .bold)).opacity(0.75)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(app.handicapEstimate.map { String(format: "%.1f", $0) } ?? "–").font(.gimme(22, .heavy))
                    Text("HCP").font(.gimme(10, .heavy)).opacity(0.8)
                }
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.15), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
            }
            HStack(spacing: 0) {
                count("\(app.pastRounds.count)", "Rounds")
                count("\(app.friends.count)", "Friends")
                count("\(app.wallet.count)", "Prizes")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient.gimmeFairway, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func count(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.gimme(20, .heavy))
            Text(label).font(.gimme(12, .bold)).opacity(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.gimme(24, .heavy))
            Text(label).font(.gimme(12, .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.gimmeSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EditProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = "🏌️"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                AvatarPicker(selection: $avatar)
                    .listRowBackground(Color.gimmeGreen.opacity(0.8))
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await app.updateProfile(name: name, avatar: avatar)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = app.me?.name ?? ""
                avatar = app.me?.avatar ?? "🏌️"
            }
        }
    }
}
