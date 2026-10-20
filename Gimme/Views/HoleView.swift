import SwiftUI

/// The GPS screen, laid out like 18Birdies: a full-screen satellite hole with the hole's
/// scorecard line across the top (number, distance to the hole, par, tee yardage, stroke index),
/// a big "plays like" distance with a club suggestion, wind and green tiles on the right,
/// shortcuts on the left, and Track Shot / Enter Score / next hole along the bottom.
struct HoleView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    let hole: Hole
    var onClose: () -> Void = {}
    var onScorecard: () -> Void = {}
    var onChat: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var projector = MapProjector()
    @State private var recenters = 0
    @State private var target: Coordinate?
    @State private var showingScoring = false
    @State private var filming = false
    @State private var goingLive = false
    @State private var watchingTrend: FeedPost?

    /// Measure from the golfer when they are on this hole, otherwise from the tee.
    private var origin: Coordinate {
        if let me = location.coordinate, Geo.distanceToSegment(me, hole.tee, hole.greenCenter) < 150 { return me }
        return hole.tee
    }

    private var holeDrops: [Drop] { app.drops.filter { $0.holeNumber == hole.number } }
    private var holeCount: Int { app.course?.holes.count ?? 18 }
    private var holeShots: [Coordinate] { app.shots[hole.number] ?? [] }

    var body: some View {
        ZStack {
            SatelliteMapView(frame: holeFrame,
                             lines: lines,
                             zones: holeDrops.map { MapZone(center: $0.center, radiusMeters: $0.radiusMeters, color: UIColor(Color.gimmeGold)) },
                             projector: projector,
                             onTap: { target = $0 })
                .overlay { markers.allowsHitTesting(false) }
                .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        if app.course?.needsMapping == true { mappingBanner }
                        if let drop = holeDrops.first { dropBanner(drop) }
                        if let clip = app.trendingHere, clip.hole == hole.number { trendingBanner(clip) }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                Spacer()
                HStack(alignment: .bottom) {
                    leftTools
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        playsLikeBubble
                        HStack(alignment: .bottom, spacing: 8) {
                            greenTile
                            windTile
                        }
                        toolsMenu
                    }
                }
                .padding(.horizontal, 12)
                bottomBar
            }

            if showingScoring {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy) { showingScoring = false } }
                VStack { Spacer(); scoringPanel }
                    .transition(.move(edge: .bottom))
            }
        }
        .onChange(of: hole) { target = nil }
        .sheet(isPresented: $filming) { NewClipSheet() }
        .sheet(isPresented: $goingLive) { GoLiveSheet() }
        .fullScreenCover(item: $watchingTrend) { clip in
            FeedPage(post: clip, isCurrent: true, watch: { _ in }, comment: { _ in })
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button { watchingTrend = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .heavy))
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.6), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .accessibilityLabel("Close")
                }
        }
    }

    /// The hottest clip from this hole, to watch and try to top.
    private func trendingBanner(_ clip: FeedPost) -> some View {
        Button { watchingTrend = clip } label: {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trending on this hole").font(.gimme(13, .heavy))
                    Text("\(clip.author.name): \(clip.title) · \(clip.likes.formatted(.number.notation(.compactName))) likes")
                        .font(.gimme(11, .bold)).lineLimit(1)
                }
                Image(systemName: "play.circle.fill").font(.system(size: 20))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 260, alignment: .leading)
        }
    }

    // MARK: Map content

    /// The hole plays straight up the screen, tee at the bottom and green near the top.
    /// `recenters` is part of the frame so the Recenter button moves the camera back.
    private var holeFrame: SatelliteMapView.Frame {
        let length = Geo.meters(hole.tee, hole.greenCenter)
        return .init(center: Geo.offset(hole.tee, meters: length * 0.55, bearing: hole.bearing),
                     distance: max(length * 2.4, 420),
                     heading: hole.bearing,
                     revision: recenters)
    }

    private var lines: [MapLine] {
        var lines: [MapLine] = []
        if !holeShots.isEmpty {
            lines.append(MapLine(points: holeShots + [origin], color: .white, width: 2))
        }
        let gold = UIColor(Color.gimmeGold)
        if let target {
            lines.append(MapLine(points: [origin, target, hole.greenCenter], color: gold, width: 3))
        } else {
            lines.append(MapLine(points: [origin, hole.greenCenter], color: gold, width: 3))
        }
        return lines
    }

    /// Pins and labels drawn in SwiftUI on top of the map, kept in place by the projector.
    private var markers: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            place(hole.tee) { Circle().fill(.white).frame(width: 10, height: 10) }
            place(hole.greenCenter) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.gimmeGold)
                    .shadow(radius: 3)
                    .offset(x: 8, y: -12)
            }
            ForEach(hole.hazards) { hazard in
                place(hazard.near) {
                    VStack(spacing: 1) {
                        Text("\(Geo.yards(origin, hazard.near))").font(.gimme(13, .heavy))
                        Text("\(Geo.yards(origin, hazard.carry))").font(.gimme(11, .bold)).opacity(0.75)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background((hazard.kind == .water ? Color.gimmeBogey : Color.black).opacity(0.7),
                                in: RoundedRectangle(cornerRadius: 6))
                }
            }
            ForEach(holeDrops) { drop in
                place(Geo.offset(drop.center, meters: drop.radiusMeters, bearing: hole.bearing + 90)) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(8)
                        .background(Color.gimmeGold, in: Circle())
                        .shadow(radius: 3)
                }
            }
            ForEach(Array(holeShots.enumerated()), id: \.offset) { index, spot in
                let next = index + 1 < holeShots.count ? holeShots[index + 1] : origin
                place(spot) { Circle().fill(.white).frame(width: 9, height: 9) }
                place(Geo.midpoint(spot, next)) { lineLabel("\(Geo.yards(spot, next))") }
            }
            if let target {
                place(target) {
                    Circle().stroke(.white, lineWidth: 3).frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                place(Geo.midpoint(origin, target)) { lineLabel("\(Geo.yards(origin, target))") }
                place(Geo.midpoint(target, hole.greenCenter)) { lineLabel("\(Geo.yards(target, hole.greenCenter))") }
            }
            if let me = location.coordinate {
                place(me) {
                    Circle().fill(Color.blue).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 2)
                }
            }
            if let credit = BundledImagery.covers(hole.tee) ? BundledImagery.credit : ImageryProvider.current.attribution {
                VStack {
                    Spacer()
                    HStack { Text(credit).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)); Spacer() }
                }
                .padding(.leading, 6).padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func place<Content: View>(_ coordinate: Coordinate, @ViewBuilder _ content: () -> Content) -> some View {
        if let point = projector.point(coordinate) {
            content().position(point)
        }
    }

    private func lineLabel(_ text: String) -> some View {
        Text(text + "y")
            .font(.gimme(13, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.75), in: Capsule())
    }

    // MARK: Numbers

    private var playsLikeTarget: Coordinate { target ?? hole.greenCenter }

    /// Height change from the golfer to the target, estimated along the hole from the tee and green heights.
    private var rise: Double? {
        guard let tee = hole.teeElevation, let green = hole.greenElevation else { return nil }
        let length = max(Geo.meters(hole.tee, hole.greenCenter), 1)
        func height(_ p: Coordinate) -> Double {
            let fraction = min(max(Geo.along(p, from: hole.tee, toward: hole.greenCenter) / length, 0), 1)
            return tee + (green - tee) * fraction
        }
        return height(playsLikeTarget) - height(origin)
    }

    private var playsLike: PlaysLike.Result {
        PlaysLike.yards(Geo.yards(origin, playsLikeTarget),
                        shotBearing: Geo.bearing(from: origin, to: playsLikeTarget),
                        rise: rise,
                        conditions: app.conditions)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            circleButton("chevron.left", label: "Minimize round", action: onClose)
            HStack(spacing: 0) {
                Text("#\(hole.number)")
                    .font(.gimme(26, .heavy))
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .background(.black.opacity(0.35))
                infoCell("To Hole", "\(Geo.yards(origin, hole.greenCenter))", unit: "Yds")
                infoCell("Par", "\(hole.par)")
                if let tee = app.selectedTee, let yards = hole.yardage(tee) {
                    infoCell(tee, "\(yards)")
                } else {
                    infoCell("Yds", "\(hole.lengthYards)")
                }
                if let handicap = hole.handicap {
                    infoCell("Handicap", "\(handicap)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.white)
            .background(Color.gimmeSurface.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer(minLength: 0)
            Button(action: onChat) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Color.gimmeLime, in: Circle())
                    .foregroundStyle(.black)
            }
            .accessibilityLabel("Group chat")
        }
        .padding(.horizontal, 12)
    }

    private func infoCell(_ title: String, _ value: String, unit: String? = nil) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.gimme(11, .bold)).opacity(0.75).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.gimme(22, .heavy)).monospacedDigit()
                if let unit { Text(unit).font(.gimme(10, .bold)).opacity(0.75) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.75), in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    private var mappingBanner: some View {
        Label("Holes not mapped yet. Use Tools › Set tee here and Set green here as you play.", systemImage: "map")
            .font(.gimme(12, .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 260, alignment: .leading)
    }

    private func dropBanner(_ drop: Drop) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(drop.prize).font(.gimme(13, .heavy)).lineLimit(1)
                Text(app.pendingChallenges.contains(drop.id) ? "Unlocked! \(drop.challenge.label)" : "\(drop.brand) · \(drop.remaining) left")
                    .font(.gimme(11, .bold)).lineLimit(1)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(LinearGradient.gimmePrize, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 230, alignment: .leading)
    }

    // MARK: Right side

    /// Big distance in a black circle, with the plays-like yardage and club beside it.
    private var playsLikeBubble: some View {
        let result = playsLike
        let actual = Geo.yards(origin, playsLikeTarget)
        return HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(actual)").font(.gimme(30, .heavy)).monospacedDigit()
                Text("y").font(.gimme(13, .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .background(Color.black, in: Circle())
            .zIndex(1)
            VStack(alignment: .leading, spacing: 0) {
                Text("Plays like").font(.gimme(13, .bold)).foregroundStyle(.black.opacity(0.7))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(result.yards)").font(.gimme(22, .heavy)).monospacedDigit()
                    Text("Yds").font(.gimme(12, .bold))
                    if let club = app.bag.club(for: result.yards) {
                        Text(club.shortName).font(.gimme(20, .heavy))
                    }
                }
                .foregroundStyle(.black)
            }
            .padding(.leading, 22).padding(.trailing, 16).padding(.vertical, 10)
            .background(.white, in: Capsule())
            .padding(.leading, -18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(actual) yards, plays like \(result.yards)")
    }

    private var greenTile: some View {
        VStack(spacing: 2) {
            Text("Green").font(.gimme(11, .heavy)).opacity(0.75)
            Text("\(Geo.yards(origin, hole.greenBack))").font(.gimme(15, .heavy))
            Text("\(Geo.yards(origin, hole.greenCenter))").font(.gimme(22, .heavy)).foregroundStyle(Color.gimmeLime)
            Text("\(Geo.yards(origin, hole.greenFront))").font(.gimme(15, .heavy))
        }
        .monospacedDigit()
        .foregroundStyle(.white)
        .frame(width: 70)
        .padding(.vertical, 8)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Green: back \(Geo.yards(origin, hole.greenBack)), middle \(Geo.yards(origin, hole.greenCenter)), front \(Geo.yards(origin, hole.greenFront))")
    }

    /// Wind arrow turned to match the map, which is rotated so the hole plays up the screen.
    private var windTile: some View {
        VStack(spacing: 4) {
            Text("Wind").font(.gimme(11, .heavy)).opacity(0.75)
            if let conditions = app.conditions {
                Image(systemName: "arrow.up")
                    .font(.system(size: 26, weight: .heavy))
                    .rotationEffect(.degrees(conditions.windFromDegrees + 180 - hole.bearing))
                Text("\(Int(conditions.windMph.rounded())) mph").font(.gimme(13, .heavy))
            } else {
                Image(systemName: "wind").font(.system(size: 22, weight: .bold)).opacity(0.6)
                Text("–").font(.gimme(13, .heavy))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 70, height: 96)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.conditions.map { "Wind \(Int($0.windMph.rounded())) miles per hour" } ?? "Wind not loaded")
    }

    private var toolsMenu: some View {
        Menu {
            if let tees = app.course?.teeNames, tees.count > 1 {
                Picker("Tees", selection: Binding(get: { app.selectedTee ?? "" }, set: { app.selectedTee = $0 })) {
                    ForEach(tees, id: \.self) { Text($0).tag($0) }
                }
            }
            if let me = location.coordinate {
                Section("Fix this hole's map") {
                    Button("Set tee here", systemImage: "mappin") { app.setSpot(tee: me) }
                    Button("Set green here", systemImage: "flag") { app.setSpot(green: me) }
                }
            }
            if !holeShots.isEmpty {
                Button("Undo last shot", systemImage: "arrow.uturn.backward") { app.undoShot() }
            }
            if location.isSimulating || app.course?.id == DemoCourse.id {
                Section("Demo: move me to") {
                    Button("Tee") { location.simulate(hole.tee) }
                    Button("Fairway") {
                        location.simulate(Geo.offset(hole.tee, meters: Geo.meters(hole.tee, hole.greenCenter) * 0.6, bearing: hole.bearing))
                    }
                    Button("Green") { location.simulate(hole.greenFront) }
                }
            }
            Button("Finish round", systemImage: "flag.checkered", action: onFinish)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 18, weight: .bold))
                Text("Tools").font(.gimme(12, .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 70, height: 56)
            .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("Tools")
    }

    // MARK: Left side

    private var leftTools: some View {
        VStack(spacing: 8) {
            tile("scope", "Recenter") {
                target = nil
                recenters += 1
            }
            tile("list.number", "Scorecard", action: onScorecard)
            tile("person.2.fill", "Group", action: onChat)
            tile("video.fill", "Clip") { filming = true }
            tile("dot.radiowaves.left.and.right", app.isLive ? "Live" : "Go live", tint: app.isLive ? Color.gimmeBirdie : nil) {
                goingLive = true
            }
        }
        .overlay(alignment: .topLeading) {
            // Your own camera while streaming, so you can see what friends see.
            if app.hostVideo.hasVideo {
                LiveVideoView(video: app.hostVideo, mirrored: false)
                    .frame(width: 64, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.gimmeBirdie, lineWidth: 2))
                    .offset(y: -96)
            }
        }
    }

    private func tile(_ icon: String, _ label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(label).font(.gimme(10, .heavy))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 56)
            .background(tint ?? .black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button { app.goToHole(hole.number - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 52)
            }
            .disabled(hole.number == 1)
            .accessibilityLabel("Previous hole")

            Button {
                app.trackShot(at: location.coordinate ?? origin)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Track Shot").font(.gimme(15, .heavy))
                        if let last = holeShots.last {
                            Text("Shot \(holeShots.count): \(Geo.yards(last, location.coordinate ?? origin)) yds")
                                .font(.gimme(11, .bold)).opacity(0.75)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }

            Button { withAnimation(.snappy) { showingScoring = true } } label: {
                Text(app.round?.strokes(app.myId, hole: hole.number).map { "Score \($0)" } ?? "Enter Score")
                    .font(.gimme(14, .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.gimmeLime, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button { app.goToHole(hole.number + 1) } label: {
                HStack(spacing: 2) {
                    Text("#\(min(hole.number + 1, holeCount))").font(.gimme(18, .heavy))
                    Image(systemName: "chevron.right")
                }
                .frame(minWidth: 56, minHeight: 52)
            }
            .disabled(hole.number == holeCount)
            .accessibilityLabel("Next hole")
        }
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: Scoring

    private var scoringPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Hole \(hole.number) · Par \(hole.par)").font(.gimme(17, .heavy))
                Spacer()
                Button("Done") { withAnimation(.snappy) { showingScoring = false } }
                    .font(.gimme(16, .heavy))
                    .foregroundStyle(Color.gimmeLime)
                    .frame(minHeight: 44)
            }
            ForEach(app.round?.players ?? []) { player in
                scoreRow(player)
            }
            if hole.number < holeCount {
                Button {
                    withAnimation(.snappy) { showingScoring = false }
                    app.goToHole(hole.number + 1)
                } label: {
                    Text("Save and go to #\(hole.number + 1)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.gimme)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .padding(.bottom, 8)
        .background(Color.gimmeSurface.ignoresSafeArea(edges: .bottom))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
    }

    private func scoreRow(_ player: Player) -> some View {
        let strokes = app.round?.strokes(player.id, hole: hole.number)
        return HStack(spacing: 10) {
            AvatarView(player: player, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.name).font(.gimme(15, .bold)).lineLimit(1)
                if let strokes {
                    Text(Scoring.label(strokes: strokes, par: hole.par))
                        .font(.gimme(12, .bold))
                        .foregroundStyle(strokes < hole.par ? Color.gimmeGold : .secondary)
                }
            }
            Spacer()
            Button { app.setStrokes(max(1, (strokes ?? hole.par) - 1), for: player, hole: hole.number) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
                    .background(Color.gimmeSurfaceRaised, in: Circle())
            }
            .accessibilityLabel("One less stroke for \(player.name)")
            Text(strokes.map { "\($0)" } ?? "–")
                .font(.gimme(26, .heavy).monospacedDigit())
                .frame(width: 40)
            Button { app.setStrokes((strokes ?? hole.par - 1) + 1, for: player, hole: hole.number) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
                    .background(Color.gimmeLime, in: Circle())
                    .foregroundStyle(.black)
            }
            .accessibilityLabel("One more stroke for \(player.name)")
        }
        .font(.system(size: 18, weight: .bold))
        .buttonStyle(.plain)
    }
}
