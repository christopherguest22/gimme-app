import SwiftUI

/// Home: your course card up top (the round you're playing, the course you're standing on,
/// your next tee time, or the featured course), your numbers, friends on the course, drops
/// and recent rounds.
struct HomeView: View {
    @Environment(AppState.self) private var app
    /// Opens Play: the live round's GPS, or a new round with this course offered first.
    var play: (CourseSummary?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if app.round == nil { greeting }
                    CourseSpotlightCard(play: play)
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

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hey \(app.me?.name ?? "golfer")").font(.gimme(24, .heavy))
            Text("GPS on every hole, a live card with your crew, and prizes waiting on the course.")
                .font(.gimme(14)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.top, 4)
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
    /// The course the golfer tapped on Home, shown first.
    var suggested: CourseSummary? = nil
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

                if let suggested {
                    Section("Playing today") {
                        Button { load(suggested) } label: {
                            HStack {
                                Label(suggested.name, systemImage: "flag.fill").font(.headline)
                                Spacer()
                                Text("Tee off").font(.gimme(14, .heavy)).foregroundStyle(Color.gimmeLime)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
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
/// Home's course card, on a satellite photo of the hole. Shows, first that applies: the round
/// in progress (on the hole you're playing), the course you're standing on, your next tee time,
/// or the featured course. The photo and the button both open Play.
struct CourseSpotlightCard: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    var play: (CourseSummary?) -> Void

    @State private var projector = MapProjector()
    @State private var editingTeeTime = false

    enum Kind { case live, here, teeTime, featured }

    /// Within this distance of a course's center, the golfer counts as being at that course.
    private static let atCourseMeters = 1_500.0

    private var kind: Kind {
        if app.round != nil { return .live }
        if herePack != nil { return .here }
        if teeTimePack != nil { return .teeTime }
        return .featured
    }

    private var herePack: PackCourse? {
        guard let point = location.coordinate else { return nil }
        return CoursePack.courses
            .map { ($0, Geo.meters(point, $0.center)) }
            .filter { $0.1 < Self.atCourseMeters }
            .min { $0.1 < $1.1 }?.0
    }

    private var teeTimePack: PackCourse? {
        guard let teeTime = app.teeTime, teeTime.isUpcoming else { return nil }
        return CoursePack.course(id: teeTime.courseId)
    }

    private var pack: PackCourse? {
        switch kind {
        case .live: app.course.flatMap { CoursePack.course(id: $0.id) }
        case .here: herePack
        case .teeTime: teeTimePack
        case .featured: CoursePack.featured
        }
    }

    private var course: Course? {
        if kind == .live { return app.course }
        return pack.flatMap { app.previewCourses[$0.id] }
    }

    /// The hole on the photo: the one being played, the one you're standing nearest, the
    /// first tee before a booked round, or the featured finishing hole.
    private var holeNumber: Int {
        switch kind {
        case .live: return app.currentHole
        case .here:
            guard let point = location.coordinate, let course else { return 1 }
            return course.holes.min {
                min(Geo.meters(point, $0.tee), Geo.meters(point, $0.greenCenter))
                    < min(Geo.meters(point, $1.tee), Geo.meters(point, $1.greenCenter))
            }?.number ?? 1
        case .teeTime: return course?.holes.map(\.number).min() ?? 1
        case .featured: return 18
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
                .contentShape(Rectangle())
                .onTapGesture(perform: primaryAction)
            details
        }
        .foregroundStyle(.white)
        .background(Color.gimmeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if kind == .live {
                RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.gimmeLime, lineWidth: 2)
            }
        }
        .task(id: pack?.id) {
            if kind != .live, let pack { await app.loadPreview(pack) }
        }
        .onAppear { location.refresh() }
        .sheet(isPresented: $editingTeeTime) { TeeTimeSheet() }
    }

    private var photo: some View {
        ZStack(alignment: .top) {
            if let hole = course?.hole(holeNumber) {
                let length = Geo.meters(hole.tee, hole.greenCenter)
                let drops = kind == .live ? app.drops.filter { $0.holeNumber == hole.number } : []
                SatelliteMapView(frame: .init(center: Geo.offset(hole.tee, meters: length * 0.5, bearing: hole.bearing),
                                              distance: max(length * 2.2, 420),
                                              heading: hole.bearing),
                                 lines: [MapLine(points: [hole.tee, hole.greenCenter], color: UIColor(Color.gimmeGold), width: 3)],
                                 zones: drops.map { MapZone(center: $0.center, radiusMeters: $0.radiusMeters, color: UIColor(Color.gimmeGold)) },
                                 projector: projector)
                    .allowsHitTesting(false)
            } else {
                Color.gimmeSurfaceRaised.overlay { ProgressView().tint(.white) }
            }
            HStack(alignment: .top) {
                holeChip
                Spacer()
                badge
            }
            .padding(10)
        }
        .frame(height: 220)
        .clipped()
    }

    private var holeChip: some View {
        HStack(spacing: 6) {
            Text("#\(holeNumber)").font(.gimme(22, .heavy))
            if let hole = course?.hole(holeNumber) {
                Text("Par \(hole.par)").font(.gimme(13, .bold))
                if let yards = hole.yardage(kind == .live ? app.selectedTee : pack?.longestTee?.name) {
                    Text("\(yards) yds").font(.gimme(13, .bold))
                }
                if let handicap = hole.handicap { Text("HCP \(handicap)").font(.gimme(13, .bold)) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var badge: some View {
        switch kind {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(Color.gimmeBirdie).frame(width: 8, height: 8)
                Text("LIVE").font(.gimme(12, .heavy))
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.black.opacity(0.7), in: Capsule())
        case .here:
            Label("You're here", systemImage: "location.fill").font(.gimme(12, .heavy))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.gimmeGreen, in: Capsule())
        case .teeTime, .featured:
            EmptyView()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker).font(.gimme(11, .heavy)).tracking(0.8)
                .foregroundStyle(kind == .live ? Color.gimmeLime : Color.gimmeGold)
            Text(kind == .live ? app.round?.courseName ?? "" : pack?.name ?? "").font(.gimme(22, .heavy))
            Text(detail).font(.gimme(13, .bold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(kind == .live ? "Open GPS" : "Play a round",
                          systemImage: kind == .live ? "location.north.line.fill" : "flag.fill")
                }
                .buttonStyle(GimmeButtonStyle(prize: kind == .live))
                if kind != .live {
                    Button { editingTeeTime = true } label: {
                        Image(systemName: "calendar.badge.plus").font(.system(size: 18, weight: .bold))
                            .frame(width: 50, height: 50)
                            .background(Color.gimmeSurfaceRaised, in: Circle())
                    }
                    .accessibilityLabel(app.teeTime == nil ? "Add a tee time" : "Change tee time")
                }
            }
        }
        .padding(16)
    }

    private var kicker: String {
        switch kind {
        case .live: "ROUND IN PROGRESS"
        case .here: "YOU'RE AT THE COURSE"
        case .teeTime: "NEXT TEE TIME"
        case .featured: "FEATURED COURSE"
        }
    }

    private var detail: String {
        switch kind {
        case .live:
            guard let round = app.round else { return "" }
            let others = round.players.filter { $0.id != app.myId }.map(\.name)
            var text = "Hole \(app.currentHole) · \(Scoring.formatToPar(round.toPar(app.myId))) thru \(round.holesPlayed(app.myId))"
            if !others.isEmpty { text += " · with \(others.formatted())" }
            return text
        case .teeTime:
            guard let teeTime = app.teeTime else { return "" }
            return teeTime.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                + (pack?.longestTee.map { " · Par \($0.par) · \($0.yardage.formatted()) yds" } ?? "")
        case .here, .featured:
            guard let tee = pack?.longestTee else { return "" }
            return "\(CoursePack.area) · Par \(tee.par) · \(tee.yardage.formatted()) yds · \(String(format: "%.1f", tee.rating))/\(tee.slope)"
        }
    }

    private func primaryAction() {
        play(kind == .live ? nil : pack?.summary)
    }
}

/// Book your next round so Home shows that course ahead of time.
struct TeeTimeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var courseId = CoursePack.featured?.id ?? ""
    @State private var date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0,
                                                    of: .now.addingTimeInterval(86_400)) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Picker("Course", selection: $courseId) {
                    ForEach(CoursePack.courses) { Text($0.name).tag($0.id) }
                }
                DatePicker("Tee time", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                if app.teeTime != nil {
                    Section {
                        Button("Remove tee time", role: .destructive) {
                            app.teeTime = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Tee time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let pack = CoursePack.course(id: courseId) {
                            app.teeTime = TeeTime(courseId: pack.id, courseName: pack.name, date: date)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let teeTime = app.teeTime {
                    courseId = teeTime.courseId
                    date = max(teeTime.date, .now)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
