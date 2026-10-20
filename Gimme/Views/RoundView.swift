import SwiftUI

/// The round, full screen: the hole map with distances and scoring, plus the scorecard
/// and group chat one tap away.
struct RoundView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var showingScorecard = false
    @State private var showingChat = false
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let round = app.round, let hole = app.hole {
                HoleView(hole: hole,
                         onClose: { dismiss() },
                         onScorecard: { showingScorecard = true },
                         onChat: { showingChat = true },
                         onFinish: { confirmFinish = true })
                    .sheet(isPresented: $showingScorecard) {
                        NavigationStack {
                            ScorecardView(round: round)
                                .navigationTitle(round.courseName)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        ShareLink(item: round.shareText) { Image(systemName: "square.and.arrow.up") }
                                    }
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingScorecard = false }
                                    }
                                }
                                .background(Color.gimmeBackground)
                        }
                        .presentationDetents([.medium, .large])
                    }
                    .sheet(isPresented: $showingChat) {
                        NavigationStack {
                            RoundChatView()
                                .navigationTitle("Group chat")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingChat = false }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                    }
                    .confirmationDialog("Finish this round?", isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button("Finish and post to feed") {
                            Task {
                                await app.finishRound()
                                location.simulate(nil)
                                dismiss()
                            }
                        }
                    }
            } else {
                ContentUnavailableView("No round in progress",
                                       systemImage: "flag",
                                       description: Text("Tap Play to start a round."))
                    .onTapGesture { dismiss() }
            }
        }
        .background(Color.gimmeBackground)
        .appMessages(active: true)
    }
}

// MARK: - Scorecard

struct ScorecardView: View {
    @Environment(AppState.self) private var app
    let round: Round

    var body: some View {
        ScrollView {
            ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cell("Hole", bold: true, wide: true)
                    ForEach(1...round.pars.count, id: \.self) { n in
                        Button { app.goToHole(n) } label: { cell("\(n)", bold: true) }
                            .buttonStyle(.plain)
                            .background(n == app.currentHole ? Color.gimmeLime.opacity(0.25) : .clear)
                    }
                    cell("Tot", bold: true)
                    cell("+/-", bold: true)
                }
                GridRow {
                    cell("Par", wide: true)
                    ForEach(round.pars.indices, id: \.self) { i in cell("\(round.pars[i])") }
                    cell("\(round.pars.reduce(0, +))")
                    cell("")
                }
                .foregroundStyle(.secondary)
                Divider()
                ForEach(round.standings) { player in
                    GridRow {
                        cell("\(player.avatar) \(player.name)", wide: true)
                        ForEach(1...round.pars.count, id: \.self) { n in
                            scoreCell(round.strokes(player.id, hole: n), par: round.pars[n - 1])
                        }
                        cell("\(round.total(player.id))", bold: true)
                        cell(Scoring.formatToPar(round.toPar(player.id)), bold: true)
                    }
                    Divider()
                }
            }
            .padding()
            }
            if round.players.count > 1 {
                SideGamesView(round: round).padding(.horizontal)
            }
        }
    }

    private func cell(_ text: String, bold: Bool = false, wide: Bool = false) -> some View {
        Text(text)
            .font(bold ? .subheadline.bold() : .subheadline)
            .lineLimit(1)
            .frame(width: wide ? 110 : 36, height: 36, alignment: wide ? .leading : .center)
    }

    /// Birdies get a circle, bogeys a square, like a paper card.
    @ViewBuilder
    private func scoreCell(_ strokes: Int?, par: Int) -> some View {
        if let strokes {
            Text("\(strokes)")
                .font(.subheadline.bold())
                .frame(width: 26, height: 26)
                .overlay {
                    if strokes < par { Circle().stroke(Color.gimmeGold, lineWidth: 1.5) }
                    else if strokes > par { Rectangle().stroke(Color.gimmeBogey, lineWidth: 1.5) }
                }
                .frame(width: 36, height: 36)
        } else {
            cell("·")
        }
    }
}

// MARK: - Chat

struct RoundChatView: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                List(app.chat) { message in
                    let mine = message.author.id == app.myId
                    HStack(alignment: .bottom, spacing: 8) {
                        if mine { Spacer(minLength: 40) } else { AvatarView(player: message.author, size: 30) }
                        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                            if !mine { Text(message.author.name).font(.caption.bold()).foregroundStyle(.secondary) }
                            Text(message.text)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(mine ? Color.black : Color.white)
                                .background(mine ? Color.gimmeLime : Color.gimmeSurfaceRaised,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                        }
                        if !mine { Spacer(minLength: 40) }
                    }
                    .listRowSeparator(.hidden)
                    .id(message.id)
                }
                .listStyle(.plain)
                .overlay {
                    if app.chat.isEmpty {
                        ContentUnavailableView("Say something to your group", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .onChange(of: app.chat.count) {
                    if let last = app.chat.last { scroller.scrollTo(last.id) }
                }
            }
            HStack {
                TextField("Message your group", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "paperplane.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        app.send(text)
        draft = ""
    }
}

// MARK: - Side games

/// Skins and Nassau standings, updated as scores come in.
struct SideGamesView: View {
    @Environment(AppState.self) private var app
    let round: Round
    @State private var editingStakes = false

    /// The freshest copy of this round, so stakes and paid marks update as soon as they change.
    private var current: Round {
        if app.round?.id == round.id, let live = app.round { return live }
        return app.pastRounds.first { $0.id == round.id } ?? round
    }

    private func player(_ id: String) -> Player? {
        current.players.first { $0.id == id }.map(app.latest)
    }

    private func name(_ id: String?) -> String {
        guard let id, let player = player(id) else { return "Tied" }
        return id == app.myId ? "You" : player.name
    }

    var body: some View {
        let round = current
        let stakes = round.stakes ?? Stakes()
        let skins = Scoring.skins(round)
        let others = Double(max(round.players.count - 1, 0))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Side games").font(.gimme(20, .bold))
                Spacer()
                Button { editingStakes = true } label: {
                    Label(stakes.isOn ? "Stakes" : "Play for money", systemImage: "dollarsign.circle.fill")
                        .font(.gimme(14, .heavy))
                }
                .foregroundStyle(Color.gimmeLime)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Skins").font(.headline)
                    if stakes.perSkin > 0 {
                        Text("\(Settlement.money(stakes.perSkin)) each").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if skins.carryover > 0 {
                        Text("\(skins.carryover + 1) skins on the next hole")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gimmeGold.opacity(0.25), in: Capsule())
                    }
                }
                ForEach(round.players) { p in
                    let won = skins.skins[p.id] ?? 0
                    HStack {
                        Text("\(p.avatar) \(p.name)")
                        Spacer()
                        if stakes.perSkin > 0 && won > 0 {
                            // Every other player pays the winner the stake for each skin.
                            Text("+\(Settlement.money(Double(won) * stakes.perSkin * others))")
                                .font(.gimme(14, .bold)).foregroundStyle(Color.gimmeLime)
                        }
                        Text("\(won)").font(.gimme(17, .bold)).frame(minWidth: 24, alignment: .trailing)
                    }
                }
            }
            .gimmeCard()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nassau").font(.headline)
                    if stakes.perNassauLeg > 0 {
                        Text("\(Settlement.money(stakes.perNassauLeg)) a leg").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                ForEach(Scoring.nassau(round)) { leg in
                    HStack {
                        Text(leg.name)
                        Spacer()
                        if leg.holesCounted == 0 {
                            Text("Not started").foregroundStyle(.secondary)
                        } else {
                            Text(leg.leader == nil ? "All square" : "\(name(leg.leader)) by \(leg.margin)")
                                .bold()
                            if leg.isFinished(holes: round.pars.count) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.gimmeLime)
                                    .accessibilityLabel("Final")
                            }
                        }
                    }
                }
            }
            .gimmeCard()

            if stakes.isOn {
                SettleUpCard(round: round)
            }
        }
        .padding(.bottom)
        .sheet(isPresented: $editingStakes) {
            StakesSheet(initial: current.stakes ?? Stakes()) { app.setStakes($0, for: current) }
                .presentationDetents([.medium])
        }
    }
}

/// Who's up, who's down, and the payments that square everyone, with Venmo and Cash App buttons.
struct SettleUpCard: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    let round: Round

    private func player(_ id: String) -> Player? { round.players.first { $0.id == id }.map(app.latest) }
    private func label(_ id: String) -> String { id == app.myId ? "You" : player(id)?.name ?? "Golfer" }

    var body: some View {
        let stakes = round.stakes ?? Stakes()
        let balances = Settlement.balances(round, stakes: stakes)
        let payments = Settlement.payments(balances)
        let paid = Set(round.paid ?? [])
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Settle up").font(.headline)
                Spacer()
                Text(round.isActive ? "So far" : "Final").font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(round.players) { p in
                let amount = balances[p.id] ?? 0
                HStack {
                    Text("\(p.avatar) \(label(p.id))")
                    Spacer()
                    Text(amount > 0.005 ? "+\(Settlement.money(amount))" : amount < -0.005 ? "−\(Settlement.money(-amount))" : "Even")
                        .font(.gimme(16, .heavy))
                        .foregroundStyle(amount > 0.005 ? Color.gimmeLime : amount < -0.005 ? Color.gimmeBogey : .secondary)
                }
            }
            if !payments.isEmpty {
                Divider()
                ForEach(payments) { payment in
                    paymentRow(payment, isPaid: paid.contains(payment.id))
                }
            }
            Text("Gimme doesn't hold or move money. Payments happen in Venmo or Cash App, and anyone in the group can mark them paid.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .gimmeCard(highlight: .gimmeGold)
    }

    @ViewBuilder
    private func paymentRow(_ payment: Payment, isPaid: Bool) -> some View {
        let note = "Gimme side games · \(round.courseName)"
        let payee = player(payment.to)
        let payer = player(payment.from)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(label(payment.from)) → \(label(payment.to))")
                    .strikethrough(isPaid)
                Spacer()
                Text(Settlement.money(payment.amount)).font(.gimme(17, .heavy)).strikethrough(isPaid)
                Button { app.togglePaid(payment, in: round) } label: {
                    Image(systemName: isPaid ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isPaid ? Color.gimmeLime : .secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isPaid ? "Marked paid. Tap to undo" : "Mark paid")
            }
            if !isPaid {
                if payment.from == app.myId {
                    HStack(spacing: 8) {
                        if let url = payee?.venmo.flatMap({ PayLinks.venmo(handle: $0, amount: payment.amount, note: note) }) {
                            Button("Pay on Venmo") { openURL(url) }.buttonStyle(.gimme)
                        }
                        if let url = payee?.cashApp.flatMap({ PayLinks.cashApp(cashtag: $0, amount: payment.amount) }) {
                            Button("Pay on Cash App") { openURL(url) }.buttonStyle(.gimme)
                        }
                    }
                    if payee?.venmo == nil && payee?.cashApp == nil {
                        Text("\(label(payment.to)) hasn't added Venmo or Cash App yet.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if payment.to == app.myId, let url = payer?.venmo.flatMap({ PayLinks.venmo(handle: $0, amount: payment.amount, note: note, request: true) }) {
                    Button("Request on Venmo") { openURL(url) }.buttonStyle(.gimme)
                }
            }
        }
    }
}

/// Edits a copy of the stakes and saves once, on Save, so the group gets one chat message.
struct StakesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stakes
    var onSave: (Stakes) -> Void

    init(initial: Stakes, onSave: @escaping (Stakes) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form { StakesEditor(stakes: $draft) }
                .navigationTitle("Stakes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(draft); dismiss() }
                    }
                }
        }
    }
}

/// Dollar amount pickers for skins and Nassau, used when starting a round and from the scorecard.
struct StakesEditor: View {
    @Binding var stakes: Stakes
    private let presets: [Double] = [0, 1, 2, 5, 10, 20]

    var body: some View {
        Section {
            row("Per skin", value: $stakes.perSkin)
            row("Per Nassau leg", value: $stakes.perNassauLeg)
        } header: {
            Text("Play for money")
        } footer: {
            Text("Skins: everyone else pays the winner this much for each skin. Nassau: everyone else pays the leader of the front 9, back 9 and overall once each one finishes.")
        }
    }

    private func row(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                TextField("0", value: value, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { amount in
                        Button(amount == 0 ? "Off" : Settlement.money(amount)) { value.wrappedValue = amount }
                            .font(.gimme(13, .heavy))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(value.wrappedValue == amount ? Color.gimmeLime : Color.gimmeSurfaceRaised, in: Capsule())
                            .foregroundStyle(value.wrappedValue == amount ? Color.black : Color.white)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
