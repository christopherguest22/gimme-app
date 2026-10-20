import SwiftUI

/// Home: a play card up top, your numbers, friends on the course, drops and recent rounds.
struct HomeView: View {
    @Environment(AppState.self) private var app
    var startRound: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    playCard
                    if app.round == nil, let pack = CoursePack.featured {
                        FeaturedCourseCard(pack: pack, onPlay: startRound)
                    }
                    statsStrip

                    let playing = app.friends.filter { $0.playingNow != nil }
                    if !playing.isEmpty {
                        SectionHeader(title: "On the course now")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(playing) { friend in
                                    HStack(spacing: 10) {
                                        AvatarView(player: friend, size: 40)
                                            .overlay(alignment: .bottomTrailing) {
                                                Circle().fill(Color.gimmeLime).frame(width: 11, height: 11)
                                                    .overlay(Circle().stroke(Color.gimmeSurface, lineWidth: 2))
                                            }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(friend.name).font(.gimme(15, .bold))
                                            Text(friend.playingNow ?? "").font(.gimme(12)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    .frame(width: 230, alignment: .leading)
                                    .gimmeCard()
                                }
                            }
                        }
                    }

                    SectionHeader(title: app.drops.isEmpty ? "Prize drops" : "Drops on this course")
                    if app.drops.isEmpty {
                        HStack(spacing: 14) {
                            Image(systemName: "gift.fill").font(.largeTitle).foregroundStyle(Color.gimmeGold)
                            Text("Brands hide prizes on holes. Look for the gold flag, reach the green during your round, and the prize is yours.")
                                .font(.gimme(14))
                        }
                        .gimmeCard(highlight: .gimmeGold)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(app.drops) { drop in DropCard(drop: drop) }
                            }
                        }
                    }

                    if !app.pastRounds.isEmpty {
                        SectionHeader(title: "Recent rounds")
                        VStack(spacing: 0) {
                            ForEach(app.pastRounds.prefix(5)) { round in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(round.courseName).font(.gimme(15, .bold))
                                        Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.gimme(12)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(round.total(app.myId))").font(.gimme(24, .heavy))
                                    Text(Scoring.formatToPar(round.toPar(app.myId)))
                                        .font(.gimme(13, .bold)).foregroundStyle(.secondary).frame(width: 34)
                                }
                                .padding(.vertical, 10)
                                if round.id != app.pastRounds.prefix(5).last?.id { Divider() }
                            }
                        }
                        .gimmeCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.gimmeBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Gimme").font(.gimme(26, .heavy)).foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let me = app.me { AvatarView(player: me, size: 34) }
                }
            }
            .toolbarBackground(Color.gimmeBackground, for: .navigationBar)
        }
    }

    private var playCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let round = app.round {
                Text("ROUND IN PROGRESS").font(.gimme(12, .heavy)).tracking(0.8).opacity(0.8)
                Text(round.courseName).font(.gimme(24, .heavy))
                Text("Hole \(app.currentHole) · \(Scoring.formatToPar(round.toPar(app.myId))) thru \(round.holesPlayed(app.myId))")
                    .font(.gimme(15, .bold)).opacity(0.9)
                Button("Resume round", action: startRound).buttonStyle(.gimmePrize)
            } else {
                Text("Hey \(app.me?.name ?? "golfer")").font(.gimme(24, .heavy))
                Text("GPS on every hole, a live card with your crew, and prizes waiting on the course.")
                    .font(.gimme(15)).opacity(0.9)
                Button(action: startRound) {
                    Label("Play golf", systemImage: "flag.fill")
                }
                .buttonStyle(.gimmePrize)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.gimmeFairway, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            stat(app.handicapEstimate.map { String(format: "%.1f", $0) } ?? "–", "Handicap")
            Divider().frame(height: 34)
            stat("\(app.pastRounds.count)", "Rounds")
            Divider().frame(height: 34)
            stat("\(app.wallet.count)", "Prizes won")
        }
        .padding(.vertical, 12)
        .background(Color.gimmeSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.gimme(22, .heavy))
            Text(label).font(.gimme(12, .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DropCard: View {
    let drop: Drop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flag.fill").foregroundStyle(Color.gimmeGold)
                Text("Hole \(drop.holeNumber)").font(.headline)
                Spacer()
                Text("\(drop.remaining) left")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.gimmeGold.opacity(0.25), in: Capsule())
            }
            Text(drop.brand).font(.caption.bold()).foregroundStyle(.secondary)
            Text(drop.prize).font(.gimme(17, .semibold)).lineLimit(2)
            Text(drop.challenge.label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 220, alignment: .leading)
        .gimmeCard(highlight: .gimmeGold)
    }
}

/// Kept for list layouts (the scorecard and brand screens).
struct DropRow: View {
    let drop: Drop

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .foregroundStyle(Color.gimmeGold)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hole \(drop.holeNumber) · \(drop.brand)").font(.headline)
                Text(drop.prize)
                Text(drop.challenge.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(drop.remaining) left")
                .font(.caption.bold())
                .padding(6)
                .background(Color.gimmeGold.opacity(0.2), in: Capsule())
        }
    }
}

/// Pick a course (demo layout or a real one from OpenStreetMap) and who's playing.
struct StartRoundView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    var onStart: () -> Void

    @State private var nearby: [CourseSummary] = []
    @State private var searching = false
    @State private var group = Set<String>()
    @State private var error: String?
    /// A loaded course waiting for the golfer to pick their tees.
    @State private var choosingTees: Course?
    @State private var stakes = Stakes()

    var body: some View {
        NavigationStack {
            List {
                Section("Who's playing") {
                    if app.friends.isEmpty {
                        Text("Add friends on the Friends tab to play together.").foregroundStyle(.secondary)
                    }
                    ForEach(app.friends) { friend in
                        Button {
                            if group.contains(friend.id) { group.remove(friend.id) } else { group.insert(friend.id) }
                        } label: {
                            HStack {
                                AvatarView(player: friend, size: 34)
                                Text(friend.name)
                                Spacer()
                                Image(systemName: group.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.gimmeLime)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                if !group.isEmpty {
                    StakesEditor(stakes: $stakes)
                }

                Section {
                    ForEach(CoursePack.courses) { pack in
                        Button { load(pack.summary) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(pack.name).font(.headline)
                                        if pack.featured {
                                            Text("FEATURED").font(.gimme(10, .heavy))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.gimmeGold, in: Capsule())
                                                .foregroundStyle(.black)
                                        }
                                    }
                                    Text(packDetail(pack)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(CoursePack.area)
                }

                Section {
                    Button {
                        let tee = location.coordinate ?? Coordinate(37.3349, -122.0090)
                        Task { offerTees(await app.weather.addElevation(to: DemoCourse.make(firstTee: tee))) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Gimme Demo Links").font(.headline)
                            Text("Practice layout starting where you stand. Use it to try GPS, scoring and drops anywhere.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Try it")
                }

                Section {
                    if searching { ProgressView() }
                    ForEach(nearby) { course in
                        Button {
                            load(course)
                        } label: {
                            HStack {
                                Text(course.name)
                                Spacer()
                                if let here = location.coordinate {
                                    Text(String(format: "%.1f mi", Geo.meters(here, course.center) / 1609.34))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: {
                    Text("Courses near you")
                } footer: {
                    Text("Course maps © OpenStreetMap contributors. Scorecards © OpenGolfAPI (ODbL). Not every course has its holes mapped yet.")
                }
            }
            .navigationTitle("New round")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await findNearby() }
            .confirmationDialog("Which tees are you playing?",
                                isPresented: Binding(get: { choosingTees != nil }, set: { if !$0 { choosingTees = nil } }),
                                titleVisibility: .visible,
                                presenting: choosingTees) { course in
                ForEach(course.teeNames, id: \.self) { tee in
                    Button("\(tee) · \(course.total(tee)) yds") { start(course, tee: tee) }
                }
            }
        }
    }

    private func packDetail(_ pack: PackCourse) -> String {
        var parts = ["Par 72"]
        if let tee = pack.longestTee { parts.append("\(tee.yardage.formatted()) yds · \(String(format: "%.1f", tee.rating))/\(tee.slope)") }
        if pack.membersOnly { parts.append("Members") }
        return parts.joined(separator: " · ")
    }

    private var players: [Player] { app.friends.filter { group.contains($0.id) } }

    /// Asks for tees when the scorecard has more than one set, otherwise starts right away.
    private func offerTees(_ course: Course) {
        if course.teeNames.count > 1 { choosingTees = course } else { start(course, tee: course.teeNames.first) }
    }

    private func start(_ course: Course, tee: String? = nil) {
        Task {
            await app.startRound(on: course, with: players, tee: tee, stakes: stakes)
            if app.round != nil {
                dismiss()
                onStart()
            }
        }
    }

    private func load(_ summary: CourseSummary) {
        Task {
            searching = true
            defer { searching = false }
            do {
                offerTees(try await app.prepareCourse(summary))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func findNearby() async {
        guard let point = location.coordinate else { return }
        searching = true
        defer { searching = false }
        nearby = (try? await app.courses.nearbyCourses(around: point)) ?? []
    }
}

/// Home showcase for the launch course: hole 18 of the Ocean Course on satellite, with its numbers.
struct FeaturedCourseCard: View {
    @Environment(AppState.self) private var app
    let pack: PackCourse
    var onPlay: () -> Void
    var holeNumber = 18

    @State private var projector = MapProjector()

    private var packHole: PackCourse.PackHole? { pack.holes.first { $0.number == holeNumber } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let hole = app.featuredCourse?.hole(holeNumber) {
                    let length = Geo.meters(hole.tee, hole.greenCenter)
                    SatelliteMapView(frame: .init(center: Geo.offset(hole.tee, meters: length * 0.5, bearing: hole.bearing),
                                                  distance: max(length * 2.2, 420),
                                                  heading: hole.bearing),
                                     lines: [MapLine(points: [hole.tee, hole.greenCenter], color: UIColor(Color.gimmeGold), width: 3)],
                                     projector: projector)
                        .allowsHitTesting(false)
                } else {
                    Color.gimmeSurfaceRaised
                        .overlay { ProgressView().tint(.white) }
                }
                HStack(spacing: 6) {
                    Text("#\(holeNumber)").font(.gimme(22, .heavy))
                    if let packHole {
                        Text("Par \(packHole.par)").font(.gimme(13, .bold))
                        if let tee = pack.longestTee, let yards = packHole.yardages[tee.name] {
                            Text("\(yards) yds").font(.gimme(13, .bold))
                        }
                        Text("HCP \(packHole.handicap)").font(.gimme(13, .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(10)
            }
            .frame(height: 210)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text("FEATURED COURSE").font(.gimme(11, .heavy)).tracking(0.8).foregroundStyle(Color.gimmeGold)
                Text(pack.name).font(.gimme(22, .heavy))
                if let tee = pack.longestTee {
                    Text("Kiawah Island · Par \(tee.par) · \(tee.yardage.formatted()) yds · \(String(format: "%.1f", tee.rating))/\(tee.slope)")
                        .font(.gimme(13, .bold)).foregroundStyle(.secondary)
                }
                Button(action: onPlay) { Label("Play a round", systemImage: "flag.fill") }
                    .buttonStyle(.gimme)
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(Color.gimmeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task { await app.loadFeatured() }
    }
}
