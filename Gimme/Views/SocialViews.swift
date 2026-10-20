import SwiftUI
import UIKit

/// Prize wallet: every prize won, with its code.
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
            if let claim = prize.drop.claimURL {
                Link(destination: claim) {
                    Label("Claim at \(prize.drop.brand)", systemImage: "arrow.up.right")
                        .font(.gimme(15, .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.black, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text("Won on hole \(prize.drop.holeNumber) · expires \(prize.drop.expires.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.black.opacity(0.7))
        }
        .padding(16)
        .background(LinearGradient.gimmePrize, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(prize.redeemed ? 0.6 : 1)
    }
}

/// The unlock moment, laid out like a brand ad: the brand's line, the product, a button to claim
/// it on the brand's site, and the green it was won on with the drop marked over the hole.
struct DropFoundView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let prize: WonPrize
    @State private var shared = false
    @State private var appeared = false
    @State private var projector = MapProjector()

    private static let cream = Color(red: 0.96, green: 0.94, blue: 0.89)
    private static let navy = Color(red: 0.09, green: 0.14, blue: 0.25)
    private static let brandGreen = Color(red: 0.12, green: 0.36, blue: 0.23)

    private var drop: Drop { prize.drop }

    var body: some View {
        ZStack(alignment: .top) {
            Self.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 14) {
                        headline
                        product
                        offer
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                }
                greenMap
            }
            // Light confetti from the top that fades out by the claim button.
            LightConfetti()
                .frame(height: 560)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.5), location: 0.5),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .foregroundStyle(Self.navy)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
        }
    }

    private var header: some View {
        HStack {
            Text("GIMME DROP · HOLE \(drop.holeNumber)")
                .font(.gimme(12, .heavy)).tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Self.brandGreen, in: Capsule())
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Self.navy.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    private var headline: some View {
        Text(drop.headline ?? "You found a drop!")
            .font(.gimme(30, .heavy))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    private var product: some View {
        ZStack {
            Circle().fill(Self.brandGreen).frame(width: 200, height: 200)
            if let url = drop.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit().padding(26)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 184, height: 184)
                .background(Color(white: 0.97))
                .clipShape(Circle())
            } else {
                Image(systemName: "gift.fill").font(.system(size: 80)).foregroundStyle(Color.gimmeGold)
            }
        }
        .scaleEffect(appeared ? 1 : 0.4)
        .rotationEffect(.degrees(appeared ? 0 : -20))
        .accessibilityLabel(drop.prize)
    }

    private var offer: some View {
        VStack(spacing: 4) {
            Text(drop.brand.uppercased()).font(.gimme(12, .heavy)).tracking(1.2).foregroundStyle(.secondary)
            Text(drop.prize).font(.gimme(24, .heavy)).multilineTextAlignment(.center)
            Text(drop.detail).font(.gimme(15, .semibold)).multilineTextAlignment(.center).opacity(0.8)
            if let claim = drop.claimURL {
                Button { openURL(claim) } label: {
                    Label("Claim at \(drop.brand)", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabel())
                        .font(.gimme(17, .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Self.navy, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 12)
            }
            Text("Code \(prize.code) is saved in your Prizes · \(drop.remaining) left")
                .font(.gimme(12, .semibold)).foregroundStyle(.secondary)
                .padding(.top, 6)
            if app.shareActivity {
                Label("Posted to the Community feed", systemImage: "checkmark.circle.fill")
                    .font(.gimme(14, .bold)).foregroundStyle(Self.brandGreen)
                    .padding(.top, 2)
            } else {
                Button(shared ? "Posted to the Community feed" : "Post to the Community feed") {
                    Task {
                        await app.share(prize)
                        shared = true
                    }
                }
                .font(.gimme(14, .bold))
                .tint(Self.brandGreen)
                .disabled(shared)
                .padding(.top, 2)
            }
        }
    }

    /// The green the drop was won on, photo from above, with the drop marked over the hole.
    private var greenMap: some View {
        let heading = app.course?.id == drop.courseId ? app.course?.hole(drop.holeNumber)?.bearing ?? 0 : 0
        return SatelliteMapView(frame: .init(center: drop.center, distance: 160, heading: heading),
                                projector: projector)
            .allowsHitTesting(false)
            .overlay {
                GeometryReader { _ in
                    if let point = projector.point(drop.center) {
                        DropPin()
                            .position(x: point.x, y: point.y - 34)
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("Hole \(drop.holeNumber) green\(app.course?.id == drop.courseId ? " · \(app.course?.name ?? "")" : "")")
                    .font(.gimme(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                if BundledImagery.covers(drop.center) {
                    Text(BundledImagery.credit).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8)).padding(12)
                }
            }
            .frame(height: 220)
            .ignoresSafeArea(edges: .bottom)
    }
}

/// Gold map pin with a gift on it; the point sits on the hole.
private struct DropPin: View {
    var body: some View {
        ZStack {
            Image(systemName: "drop.fill")
                .resizable().scaledToFit()
                .frame(width: 52, height: 68)
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.gimmeGold)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 3)
            Image(systemName: "gift.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.09, green: 0.14, blue: 0.25))
                .offset(y: -6)
        }
        .accessibilityLabel("Drop on the hole")
    }
}

/// Puts a label's icon after its title.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

/// A gentle, endless drizzle of small confetti in the brand's colors.
private struct LightConfetti: View {
    private let pieces = (0..<44).map { _ in
        (x: CGFloat.random(in: 0...1), delay: Double.random(in: 0...4), duration: Double.random(in: 4...7),
         color: [Color(red: 0.12, green: 0.36, blue: 0.23), Color(red: 0.09, green: 0.14, blue: 0.25),
                 .gimmeGold, Color(red: 0.56, green: 0.73, blue: 0.63)].randomElement()!,
         size: CGSize(width: CGFloat.random(in: 4...6), height: CGFloat.random(in: 6...10)),
         spin: Double.random(in: 120...480))
    }
    @State private var falling = false

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces.indices, id: \.self) { i in
                let piece = pieces[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .position(x: piece.x * geo.size.width, y: falling ? geo.size.height : -12)
                    .animation(.linear(duration: piece.duration).delay(piece.delay).repeatForever(autoreverses: false),
                               value: falling)
            }
        }
        .onAppear { falling = true }
        .accessibilityHidden(true)
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
    @State private var venmo = ""
    @State private var cashApp = ""
    @State private var homeCourse = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                AvatarPicker(selection: $avatar)
                    .listRowBackground(Color.gimmeGreen.opacity(0.8))
                Section {
                    Picker("Home course", selection: $homeCourse) {
                        Text("None").tag("")
                        ForEach(CoursePack.courses) { Text($0.name).tag($0.name) }
                    }
                    Toggle("Post my prizes, holes and live rounds", isOn: Bindable(app).shareActivity)
                } header: {
                    Text("Community")
                } footer: {
                    Text("Your home course shows under your name on your posts. Posting shares prizes you win, holes where a clip is trending, and when you go live.")
                }
                Section {
                    TextField("Venmo username", text: $venmo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Cash App $cashtag", text: $cashApp)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Get paid for side games")
                } footer: {
                    Text("Friends see these so they can pay you skins and Nassau winnings in Venmo or Cash App.")
                }
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await app.updateProfile(name: name, avatar: avatar)
                            await app.updatePayHandles(venmo: venmo, cashApp: cashApp)
                            if homeCourse != (app.me?.homeCourse ?? "") { await app.updateHomeCourse(homeCourse) }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = app.me?.name ?? ""
                avatar = app.me?.avatar ?? "🏌️"
                venmo = app.me?.venmo ?? ""
                cashApp = app.me?.cashApp ?? ""
                homeCourse = app.me?.homeCourse ?? ""
            }
        }
    }
}
