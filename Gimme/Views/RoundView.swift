import SwiftUI

struct RoundView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @State private var pane = Pane.hole
    @State private var confirmFinish = false

    enum Pane: String, CaseIterable { case hole = "Hole", scorecard = "Scorecard", chat = "Chat" }

    var body: some View {
        NavigationStack {
            Group {
                if let round = app.round, let hole = app.hole {
                    VStack(spacing: 0) {
                        Picker("View", selection: $pane) {
                            ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                        switch pane {
                        case .hole: HoleView(hole: hole)
                        case .scorecard: ScorecardView(round: round)
                        case .chat: RoundChatView()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            ShareLink(item: round.shareText) { Image(systemName: "square.and.arrow.up") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Finish") { confirmFinish = true }
                        }
                    }
                    .navigationTitle(round.courseName)
                    .navigationBarTitleDisplayMode(.inline)
                    .confirmationDialog("Finish this round?", isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button("Finish and post to feed") {
                            Task {
                                await app.finishRound()
                                location.simulate(nil)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No round in progress",
                                           systemImage: "flag",
                                           description: Text("Start a round from Home to get GPS distances, a live scorecard and prize drops."))
                }
            }
        }
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
                            .background(n == app.currentHole ? Color.gimmeGreen.opacity(0.2) : .clear)
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
                    if strokes < par { Circle().stroke(Color.gimmeBirdie, lineWidth: 1.5) }
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
                                .foregroundStyle(mine ? Color.white : Color.primary)
                                .background(mine ? Color.gimmeGreen : Color(.secondarySystemBackground),
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
    let round: Round

    private func name(_ id: String?) -> String {
        guard let id, let player = round.players.first(where: { $0.id == id }) else { return "Tied" }
        return "\(player.avatar) \(player.name)"
    }

    var body: some View {
        let skins = Scoring.skins(round)
        VStack(alignment: .leading, spacing: 12) {
            Text("Side games").font(.gimme(20, .bold))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Skins").font(.headline)
                    Spacer()
                    if skins.carryover > 0 {
                        Text("\(skins.carryover + 1) skins on the next hole")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gimmeGold.opacity(0.25), in: Capsule())
                    }
                }
                ForEach(round.players) { player in
                    HStack {
                        Text("\(player.avatar) \(player.name)")
                        Spacer()
                        Text("\(skins.skins[player.id] ?? 0)").font(.gimme(17, .bold))
                    }
                }
            }
            .gimmeCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Nassau").font(.headline)
                ForEach(Scoring.nassau(round)) { leg in
                    HStack {
                        Text(leg.name)
                        Spacer()
                        if leg.holesCounted == 0 {
                            Text("Not started").foregroundStyle(.secondary)
                        } else {
                            Text(leg.leader == nil ? "All square" : "\(name(leg.leader)) by \(leg.margin)")
                                .bold()
                        }
                    }
                }
            }
            .gimmeCard()
        }
        .padding(.bottom)
    }
}
