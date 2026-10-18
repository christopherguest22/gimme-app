import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    var startRound: () -> Void
    @State private var choosingCourse = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let round = app.round {
                        Button {
                            startRound()
                        } label: {
                            Label("Back to your round at \(round.courseName)", systemImage: "flag.fill")
                                .font(.headline)
                        }
                    } else {
                        Button {
                            choosingCourse = true
                        } label: {
                            Label("Start a round", systemImage: "play.circle.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }
                }

                let playing = app.friends.filter { $0.playingNow != nil }
                if !playing.isEmpty {
                    Section("Friends playing now") {
                        ForEach(playing) { friend in
                            HStack {
                                Text(friend.avatar).font(.title2)
                                VStack(alignment: .leading) {
                                    Text(friend.name).font(.headline)
                                    Text(friend.playingNow ?? "").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Prize drops on this course") {
                    if app.drops.isEmpty {
                        Text("Start a round to see which holes have drops.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(app.drops) { drop in
                        DropRow(drop: drop)
                    }
                }

                if !app.pastRounds.isEmpty {
                    Section("Recent rounds") {
                        ForEach(app.pastRounds) { round in
                            HStack {
                                Text(round.courseName)
                                Spacer()
                                Text("\(round.total(app.me.id))").bold()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gimme")
            .sheet(isPresented: $choosingCourse) {
                StartRoundView { startRound() }
            }
        }
    }
}

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
                    ForEach(app.friends) { friend in
                        Button {
                            if group.contains(friend.id) { group.remove(friend.id) } else { group.insert(friend.id) }
                        } label: {
                            HStack {
                                Text("\(friend.avatar)  \(friend.name)")
                                Spacer()
                                if group.contains(friend.id) { Image(systemName: "checkmark.circle.fill") }
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
                        Button(course.name) { load(course) }
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
            dismiss()
            onStart()
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
