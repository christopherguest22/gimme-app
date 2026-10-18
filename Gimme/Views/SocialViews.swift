import SwiftUI
import UIKit

struct FeedView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Post to your friends", text: $draft)
                        Button("Post") {
                            let text = draft
                            draft = ""
                            Task {
                                try? await app.backend.publish(FeedPost(author: app.me, kind: .note, title: text, detail: ""))
                                await app.load()
                            }
                        }
                        .disabled(draft.isEmpty)
                    }
                }

                Section("Friends") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(app.friends) { friend in
                                VStack {
                                    Text(friend.avatar).font(.largeTitle)
                                    Text(friend.name).font(.caption.bold())
                                    Text(friend.handicap.map { String(format: "%.1f", $0) } ?? "–")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Feed") {
                    ForEach(app.feed) { post in
                        FeedRow(post: post)
                    }
                }
            }
            .navigationTitle("Friends")
            .refreshable { await app.load() }
        }
    }
}

struct FeedRow: View {
    @Environment(AppState.self) private var app
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(post.author.avatar)
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
                    List(app.wallet) { prize in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(prize.drop.brand).font(.caption.bold()).foregroundStyle(.secondary)
                            Text(prize.drop.prize).font(.headline)
                            Text(prize.drop.detail).font(.subheadline)
                            HStack {
                                Text(prize.code)
                                    .font(.system(.body, design: .monospaced).bold())
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = prize.code
                                } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(8)
                            .background(Color.gimmeGold.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            Text("Won on hole \(prize.drop.holeNumber) · expires \(prize.drop.expires.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Prize wallet")
        }
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
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "gift.fill")
                .font(.system(size: 90))
                .foregroundStyle(Color.gimmeGold)
                .scaleEffect(appeared ? 1 : 0.3)
                .rotationEffect(.degrees(appeared ? 0 : -30))
            Text("You found a drop!").font(.largeTitle.bold())
            Text(prize.drop.brand).font(.title3).foregroundStyle(.secondary)
            Text(prize.drop.prize).font(.title2.bold()).multilineTextAlignment(.center)
            Text(prize.drop.detail).multilineTextAlignment(.center)
            Text("\(prize.drop.remaining) left").font(.caption.bold())
            Spacer()
            Button {
                Task {
                    await app.share(prize)
                    shared = true
                }
            } label: {
                Label(shared ? "Shared with your group" : "Share with your group", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(shared)
            Button {
                dismiss()
            } label: {
                Text("Added to your wallet").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { appeared = true }
        }
    }
}

struct ProfileView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Text(app.me.avatar).font(.system(size: 56))
                        VStack(alignment: .leading) {
                            Text(app.me.name).font(.title2.bold())
                            Text("\(app.friends.count) friends · \(app.pastRounds.count) rounds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    LabeledContent("Handicap estimate",
                                   value: app.handicapEstimate.map { String(format: "%.1f", $0) } ?? "Play 3 full rounds")
                    LabeledContent("Prizes won", value: "\(app.wallet.count)")
                    if let best = app.pastRounds.filter({ $0.holesPlayed(app.me.id) == 18 }).map({ $0.total(app.me.id) }).min() {
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
                        HStack {
                            VStack(alignment: .leading) {
                                Text(round.courseName)
                                Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(round.total(app.me.id))").bold()
                            Text(Scoring.formatToPar(round.toPar(app.me.id))).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}
