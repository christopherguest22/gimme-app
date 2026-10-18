import SwiftUI
import UIKit

struct FeedView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @State private var addingFriend = false
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Button { addingFriend = true } label: {
                                VStack {
                                    Image(systemName: "plus")
                                        .font(.title2.bold())
                                        .frame(width: 52, height: 52)
                                        .background(Color.gimmeGreen.opacity(0.15), in: Circle())
                                    Text("Add").font(.caption.bold())
                                }
                            }
                            .buttonStyle(.plain)
                            ForEach(app.friends) { friend in
                                VStack {
                                    AvatarView(player: friend, size: 52)
                                        .overlay(alignment: .bottomTrailing) {
                                            if friend.playingNow != nil {
                                                Circle().fill(.green).frame(width: 12, height: 12)
                                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                            }
                                        }
                                    Text(friend.name).font(.caption.bold())
                                    Text(friend.handicap.map { String(format: "%.1f", $0) } ?? "–")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Friends")
                }

                Section {
                    HStack {
                        TextField("Post to your friends", text: $draft)
                        Button("Post") {
                            let text = draft
                            draft = ""
                            Task { await app.post(text) }
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Feed") {
                    if app.feed.isEmpty {
                        Text("Rounds and prizes from you and your friends show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(app.feed) { post in
                        FeedRow(post: post)
                    }
                }
            }
            .navigationTitle("Friends")
            .refreshable { await app.load() }
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
                Text("Your friend's handle is on their Profile tab.")
            }
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
                    .background(Color(.systemGroupedBackground))
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

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        if let me = app.me { AvatarView(player: me, size: 72) }
                        VStack(alignment: .leading) {
                            Text(app.me?.name ?? "").font(.gimme(24, .bold))
                            Text("\(app.friends.count) friends · \(app.pastRounds.count) rounds")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = true }
                    }
                }
                Section {
                    LabeledContent("Handicap estimate",
                                   value: app.handicapEstimate.map { String(format: "%.1f", $0) } ?? "Play 3 full rounds")
                    LabeledContent("Prizes won", value: "\(app.wallet.count)")
                    if let best = app.pastRounds.filter({ $0.holesPlayed(app.myId) == 18 }).map({ $0.total(app.myId) }).min() {
                        LabeledContent("Best 18", value: "\(best)")
                    }
                } footer: {
                    Text("An estimate using the World Handicap System method, not an official handicap index.")
                }
                Section("Round history") {
                    if app.pastRounds.isEmpty {
                        Text("Finished rounds show up here.").foregroundStyle(.secondary)
                    }
                    ForEach(app.pastRounds) { round in
                        NavigationLink {
                            ScorecardView(round: round).navigationTitle(round.courseName)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(round.courseName)
                                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(round.total(app.myId))").bold()
                                Text(Scoring.formatToPar(round.toPar(app.myId))).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $editing) { EditProfileView() }
        }
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
