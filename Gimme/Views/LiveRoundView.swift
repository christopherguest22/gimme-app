import SwiftUI

/// Watching a friend's round live: their camera when they stream it, the satellite hole with
/// where they're standing, everyone's score as it goes in, and cheers from the people watching.
struct LiveRoundView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let roundId: UUID

    @State private var round: Round?
    @State private var course: Course?
    @State private var position: LivePosition?
    @State private var cheers: [LiveCheer] = []
    @State private var ended = false
    @State private var failed = false
    @State private var draft = ""
    @State private var video = LiveVideo()
    @State private var projector = MapProjector()

    /// The golfer who went live: the one sending positions, or the first player.
    private var host: Player? {
        round?.players.first { $0.id == position?.playerId } ?? round?.players.first
    }

    private var holeNumber: Int {
        if let position { return position.hole }
        guard let round, let host else { return 1 }
        return min(round.holesPlayed(host.id) + 1, round.pars.count)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if video.hasVideo {
                    LiveVideoView(video: video)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            map.frame(width: 130, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 2))
                                .padding(12)
                                .padding(.bottom, 150)
                        }
                } else {
                    map.frame(maxHeight: .infinity)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                scoreStrip
                Spacer()
                cheerList
                cheerBar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if ended || failed { endCard }
        }
        .foregroundStyle(.white)
        .task { await start() }
        .onDisappear { Task { await video.stop() } }
    }

    // MARK: Pieces

    private var map: some View {
        ZStack {
            if let hole = course?.hole(holeNumber) {
                let length = Geo.meters(hole.tee, hole.greenCenter)
                SatelliteMapView(frame: .init(center: Geo.offset(hole.tee, meters: length * 0.55, bearing: hole.bearing),
                                              distance: max(length * 2.3, 400), heading: hole.bearing),
                                 lines: [MapLine(points: [position?.point ?? hole.tee, hole.greenCenter],
                                                 color: UIColor(Color.gimmeGold), width: 3)],
                                 projector: projector)
                    .overlay { marker(hole) }
            } else {
                LinearGradient.gimmeFairway.overlay { ProgressView().tint(.white) }
            }
        }
    }

    /// The golfer's dot and the distance left to the pin.
    private func marker(_ hole: Hole) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let position, let point = projector.point(position.point), let host {
                VStack(spacing: 3) {
                    Text("\(Geo.yards(position.point, hole.greenCenter)) to pin")
                        .font(.gimme(12, .heavy))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.black.opacity(0.7), in: Capsule())
                    AvatarView(player: host, size: 34)
                        .overlay(Circle().stroke(Color.gimmeBirdie, lineWidth: 3))
                }
                .position(x: point.x, y: point.y - 18)
                .animation(.easeInOut(duration: 1), value: position)
            }
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if let host { AvatarView(player: host, size: 38) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(host?.name ?? "Loading").font(.gimme(16, .heavy))
                    Text("LIVE").font(.gimme(11, .heavy))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.gimmeBirdie, in: Capsule())
                }
                if let round {
                    Text("Hole \(holeNumber) · \(round.courseName)").font(.gimme(12, .bold)).opacity(0.85)
                }
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .heavy))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Everyone in the group: score to par and holes played.
    private var scoreStrip: some View {
        HStack(spacing: 8) {
            ForEach(round?.players ?? []) { player in
                if let round {
                    VStack(spacing: 1) {
                        Text(player.name).font(.gimme(12, .bold)).lineLimit(1)
                        Text(Scoring.formatToPar(round.toPar(player.id))).font(.gimme(18, .heavy))
                        Text("thru \(round.holesPlayed(player.id))").font(.gimme(10, .bold)).opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var cheerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(cheers.suffix(5)) { cheer in
                HStack(spacing: 6) {
                    AvatarView(player: cheer.author, size: 24)
                    Text(cheer.author.name).font(.gimme(13, .heavy))
                    Text(cheer.text).font(.gimme(13, .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.5), in: Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: cheers)
    }

    private var cheerBar: some View {
        HStack(spacing: 8) {
            ForEach(["👏", "🔥", "⛳️"], id: \.self) { emoji in
                Button { send(emoji) } label: {
                    Text(emoji).font(.system(size: 22))
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.55), in: Circle())
                }
            }
            TextField("Cheer them on", text: $draft)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .submitLabel(.send)
                .onSubmit { send(draft) }
        }
    }

    private var endCard: some View {
        VStack(spacing: 12) {
            Text(failed ? "This round isn't live" : "Round's over").font(.gimme(24, .heavy))
            if let round, !failed {
                ForEach(round.players) { player in
                    Text("\(player.name): \(round.total(player.id)) (\(Scoring.formatToPar(round.toPar(player.id))))")
                        .font(.gimme(16, .bold))
                }
            }
            Button("Close") { dismiss() }.buttonStyle(.gimme).frame(width: 200)
        }
        .padding(24)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Live data

    private func start() async {
        do {
            let watched = try await app.backend.watch(roundId: roundId)
            round = watched.round
            course = watched.course
        } catch {
            failed = true
            return
        }
        Task {
            if let access = await app.videoAccess(roundId: roundId, publish: false) {
                await video.start(access, publish: false)
            }
        }
        for await event in app.backend.liveEvents(roundId: roundId) {
            switch event {
            case .score(let playerId, let hole, let strokes):
                round?.setStrokes(strokes, for: playerId, hole: hole)
            case .position(let update):
                position = update
            case .cheer(let cheer):
                cheers.append(cheer)
            case .clip:
                break
            case .ended:
                ended = true
                await video.stop()
            }
        }
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let me = app.me else { return }
        draft = ""
        cheers.append(LiveCheer(author: me, text: clean))
        Task { try? await app.backend.cheer(clean, roundId: roundId) }
    }
}

/// The golfer's controls for going live: let friends watch, and stream the camera.
struct GoLiveSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Let friends watch this round", isOn: Binding(
                        get: { app.isLive },
                        set: { on in
                            working = true
                            Task {
                                await app.setLive(on)
                                if !on { await app.hostVideo.stop() }
                                working = false
                            }
                        }))
                } footer: {
                    Text("Friends see where you are on the hole, every score as it goes in, and your clips. They can send cheers.")
                }
                Section {
                    Toggle("Stream my camera", isOn: Binding(
                        get: { app.hostVideo.state == .on || app.hostVideo.state == .connecting },
                        set: { on in
                            working = true
                            Task {
                                if on, let round = app.round, let access = await app.videoAccess(roundId: round.id, publish: true) {
                                    await app.hostVideo.start(access, publish: true)
                                } else if on {
                                    app.message = LiveVideoError.notSetUp.localizedDescription
                                } else {
                                    await app.hostVideo.stop()
                                }
                                working = false
                            }
                        }))
                        .disabled(!app.isLive)
                    if app.hostVideo.state == .on {
                        Toggle("Microphone", isOn: Binding(get: { app.hostVideo.micOn },
                                                           set: { _ in Task { await app.hostVideo.toggleMic() } }))
                    }
                    if case .failed(let reason) = app.hostVideo.state {
                        Text(reason).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Your phone's camera streams to friends watching. Prop it in the cart or on your bag.")
                }
            }
            .disabled(working)
            .navigationTitle("Go live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
