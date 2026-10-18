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
                                location.stopRound()
                            }
                        }
                    }
                    .onAppear { location.startRound() }
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
        ScrollView([.horizontal, .vertical]) {
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
                    if strokes < par { Circle().stroke(Color.red, lineWidth: 1.5) }
                    else if strokes > par { Rectangle().stroke(Color.blue, lineWidth: 1.5) }
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
                    HStack(alignment: .top) {
                        Text(message.author.avatar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.author.name).font(.caption.bold())
                            Text(message.text)
                        }
                        Spacer()
                        Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    .id(message.id)
                }
                .listStyle(.plain)
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
