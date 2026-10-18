import MapKit
import SwiftUI

/// The GPS screen, map first: the satellite hole fills the screen with the hole info top left,
/// back/middle/front yardages down the right edge, hazard yardages on the map itself,
/// tap-to-measure, a gold prize zone, and a hole switcher with score entry at the bottom.
struct HoleView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    let hole: Hole
    var onClose: () -> Void = {}
    var onScorecard: () -> Void = {}
    var onChat: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var camera: MapCameraPosition = .automatic
    @State private var measurePoint: Coordinate?
    @State private var scoringExpanded = true

    /// Measure from the golfer when they are on this hole, otherwise from the tee.
    private var origin: Coordinate {
        if let me = location.coordinate, Geo.distanceToSegment(me, hole.tee, hole.greenCenter) < 150 { return me }
        return hole.tee
    }

    private var holeDrops: [Drop] { app.drops.filter { $0.holeNumber == hole.number } }
    private var holeCount: Int { app.course?.holes.count ?? 18 }

    var body: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let drop = holeDrops.first { dropBanner(drop) }
                        if location.isSimulating || app.course?.id == DemoCourse.id { simulator }
                    }
                    Spacer(minLength: 8)
                    distanceColumn
                }
                .padding(.horizontal, 12)
                Spacer()
                if let measurePoint {
                    measureChip(measurePoint)
                }
                bottomPanel
            }
        }
        .onAppear { frameHole() }
        .onChange(of: hole) { measurePoint = nil; frameHole() }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.zoom, .pan]) {
                if let measurePoint {
                    MapPolyline(coordinates: [origin.clCoordinate, measurePoint.clCoordinate, hole.greenCenter.clCoordinate])
                        .stroke(.white, lineWidth: 2.5)
                    Annotation("Target", coordinate: measurePoint.clCoordinate) {
                        Circle().stroke(.white, lineWidth: 2.5).frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                } else {
                    MapPolyline(coordinates: [origin.clCoordinate, hole.greenCenter.clCoordinate])
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }

                Annotation("Tee", coordinate: hole.tee.clCoordinate) {
                    Circle().fill(.white).frame(width: 10, height: 10)
                }
                Annotation("Pin", coordinate: hole.greenCenter.clCoordinate) {
                    Image(systemName: "flag.fill").foregroundStyle(.white).font(.title3).shadow(radius: 3)
                }
                ForEach(hole.hazards) { hazard in
                    // Hazard yardages sit on the map next to the hazard, so the eye never leaves the hole.
                    Annotation(hazard.label, coordinate: hazard.near.clCoordinate) {
                        VStack(spacing: 2) {
                            Text("\(Geo.yards(origin, hazard.near))").font(.gimme(13, .heavy))
                            Text("\(Geo.yards(origin, hazard.carry))").font(.gimme(11, .bold)).opacity(0.75)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background((hazard.kind == .water ? Color.gimmeBogey : Color.black).opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                ForEach(holeDrops) { drop in
                    MapCircle(center: drop.center.clCoordinate, radius: drop.radiusMeters)
                        .foregroundStyle(Color.gimmeGold.opacity(0.2))
                        .stroke(Color.gimmeGold, lineWidth: 2)
                    Annotation(drop.brand, coordinate: Geo.offset(drop.center, meters: 28, bearing: hole.bearing + 90).clCoordinate) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(.black)
                            .padding(7)
                            .background(Color.gimmeGold, in: Circle())
                            .shadow(radius: 3)
                    }
                }
                if let me = location.coordinate {
                    Annotation("You", coordinate: me.clCoordinate) {
                        Circle().fill(Color.blue).frame(width: 15, height: 15)
                            .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                }
            }
            .mapStyle(.imagery)
            .annotationTitles(.hidden)
            .onTapGesture { screenPoint in
                if let tapped = proxy.convert(screenPoint, from: .local) {
                    measurePoint = Coordinate(tapped)
                }
            }
        }
    }

    /// Rotate the map so the hole plays straight up the screen.
    private func frameHole() {
        let lengthMeters = Geo.meters(hole.tee, hole.greenCenter)
        let middle = Geo.offset(hole.tee, meters: lengthMeters * 0.5, bearing: hole.bearing)
        camera = .camera(MapCamera(centerCoordinate: middle.clCoordinate,
                                   distance: max(lengthMeters * 2.6, 480),
                                   heading: hole.bearing,
                                   pitch: 0))
    }

    // MARK: Overlays

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            roundButton("chevron.down", label: "Minimize round", action: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(hole.number)").font(.gimme(34, .heavy))
                    Text("HOLE").font(.gimme(11, .heavy)).opacity(0.7)
                }
                Text("Par \(hole.par) · \(hole.lengthYards) yds").font(.gimme(13, .bold)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
            roundButton("list.number", label: "Scorecard", action: onScorecard)
            roundButton("bubble.left.and.bubble.right.fill", label: "Group chat", action: onChat)
            Menu {
                Button("Finish round", systemImage: "flag.checkered", action: onFinish)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55), in: Circle())
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }

    /// Back on top, middle large, front below: the order the green sits on the screen.
    private var distanceColumn: some View {
        VStack(spacing: 6) {
            yardage("BACK", hole.greenBack, size: 20)
            Divider().overlay(.white.opacity(0.3))
            yardage("MIDDLE", hole.greenCenter, size: 40)
            Divider().overlay(.white.opacity(0.3))
            yardage("FRONT", hole.greenFront, size: 20)
        }
        .frame(width: 92)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func yardage(_ label: String, _ point: Coordinate, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text("\(Geo.yards(origin, point))").font(.gimme(size, .heavy)).monospacedDigit()
            Text(label).font(.gimme(10, .heavy)).opacity(0.7)
        }
    }

    private func measureChip(_ point: Coordinate) -> some View {
        HStack(spacing: 12) {
            Label("\(Geo.yards(origin, point)) to target", systemImage: "scope")
            Text("\(Geo.yards(point, hole.greenCenter)) to pin").opacity(0.8)
            Button { measurePoint = nil } label: { Image(systemName: "xmark.circle.fill") }
                .accessibilityLabel("Clear target")
        }
        .font(.gimme(14, .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.65), in: Capsule())
        .padding(.bottom, 8)
    }

    /// Demo controls: jump your position around the hole to try distances and drops.
    private var simulator: some View {
        HStack(spacing: 6) {
            Button("Tee") { location.simulate(hole.tee) }
            Button("Fairway") {
                location.simulate(Geo.offset(hole.tee, meters: Geo.meters(hole.tee, hole.greenCenter) * 0.6, bearing: hole.bearing))
            }
            Button("Green") { location.simulate(hole.greenFront) }
        }
        .font(.gimme(12, .bold))
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.6))
        .foregroundStyle(.white)
        .accessibilityLabel("Demo: move to")
    }

    private func dropBanner(_ drop: Drop) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill").foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 1) {
                Text(drop.prize).font(.gimme(13, .heavy)).lineLimit(1)
                Text(app.pendingChallenges.contains(drop.id) ? "Unlocked! \(drop.challenge.label)" : "\(drop.brand) · \(drop.remaining) left")
                    .font(.gimme(11, .bold)).lineLimit(1)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(LinearGradient.gimmePrize, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 220, alignment: .leading)
    }

    // MARK: Hole switcher and scoring

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Button { app.goToHole(hole.number - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(hole.number == 1)
                .accessibilityLabel("Previous hole")
                Spacer()
                Button { withAnimation(.snappy) { scoringExpanded.toggle() } } label: {
                    VStack(spacing: 2) {
                        Text("Hole \(hole.number) of \(holeCount)").font(.gimme(16, .heavy))
                        Image(systemName: scoringExpanded ? "chevron.compact.down" : "chevron.compact.up")
                            .font(.system(size: 18, weight: .bold)).opacity(0.6)
                    }
                }
                .accessibilityLabel(scoringExpanded ? "Hide scoring" : "Show scoring")
                Spacer()
                Button { app.goToHole(hole.number + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(hole.number == holeCount)
                .accessibilityLabel("Next hole")
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)

            if scoringExpanded {
                VStack(spacing: 8) {
                    ForEach(app.round?.players ?? []) { player in
                        scoreRow(player)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color.gimmeSurface.opacity(0.97).ignoresSafeArea(edges: .bottom))
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
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }
}
