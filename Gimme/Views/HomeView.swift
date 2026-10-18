import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    var startRound: () -> Void
    @State private var choosingCourse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero

                    let playing = app.friends.filter { $0.playingNow != nil }
                    if !playing.isEmpty {
                        sectionTitle("Friends playing now")
                        ForEach(playing) { friend in
                            HStack(spacing: 12) {
                                AvatarView(player: friend)
                                VStack(alignment: .leading) {
                                    Text(friend.name).font(.headline)
                                    Text(friend.playingNow ?? "").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Circle().fill(.green).frame(width: 10, height: 10)
                            }
                            .gimmeCard()
                        }
                    }

                    sectionTitle(app.round == nil ? "How prize drops work" : "Prize drops on this course")
                    if app.drops.isEmpty {
                        HStack(spacing: 14) {
                            Image(systemName: "gift.fill").font(.largeTitle).foregroundStyle(Color.gimmeGold)
                            Text("Brands hide prizes on holes. Look for the gold flag, reach the green during your round, and the prize is yours.")
                                .font(.subheadline)
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
                        sectionTitle("Recent rounds")
                        ForEach(app.pastRounds.prefix(5)) { round in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(round.courseName).font(.headline)
                                    Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(round.total(app.myId))").font(.gimme(24, .bold))
                                Text(Scoring.formatToPar(round.toPar(app.myId))).foregroundStyle(.secondary)
                            }
                            .gimmeCard()
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Gimme")
            .sheet(isPresented: $choosingCourse) {
                StartRoundView { startRound() }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hey \(app.me?.name ?? "golfer") 👋")
                .font(.gimme(26, .bold))
                .foregroundStyle(.white)
            if let round = app.round {
                Text("You're on hole \(app.currentHole) at \(round.courseName).")
                    .foregroundStyle(.white.opacity(0.9))
                Button("Back to your round", action: startRound).buttonStyle(.gimmePrize)
            } else {
                Text("Track every shot, play with your crew, and win gear on the course.")
                    .foregroundStyle(.white.opacity(0.9))
                Button("Start a round") { choosingCourse = true }.buttonStyle(.gimmePrize)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.gimmeFairway, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.gimme(20, .bold)).padding(.top, 4)
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
                                    .foregroundStyle(Color.gimmeGreen)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button {
                        let tee = location.coordinate ?? Coordinate(37.3349, -122.0090)
                        start(DemoCourse.make(firstTee: tee))
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
                    Text("Course maps © OpenStreetMap contributors. Not every course has its holes mapped yet.")
                }
            }
            .navigationTitle("New round")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await findNearby() }
        }
    }

    private var players: [Player] { app.friends.filter { group.contains($0.id) } }

    private func start(_ course: Course) {
        Task {
            await app.startRound(on: course, with: players)
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
                start(try await app.courses.loadCourse(summary))
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
