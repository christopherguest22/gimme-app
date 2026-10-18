import MapKit
import SwiftUI

/// The GPS screen: satellite hole map, front/middle/back yardages, hazards, tap-to-measure,
/// a gold flag for any prize drop, and score entry for the group.
struct HoleView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationService.self) private var location
    let hole: Hole

    @State private var camera: MapCameraPosition = .automatic
    @State private var measurePoint: Coordinate?

    /// Measure from the golfer when they are on this hole, otherwise from the tee.
    private var origin: Coordinate {
        if let me = location.coordinate, Geo.distanceToSegment(me, hole.tee, hole.greenCenter) < 150 { return me }
        return hole.tee
    }

    private var holeDrops: [Drop] { app.drops.filter { $0.holeNumber == hole.number } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                map
                VStack(spacing: 8) {
                    distanceCard
                    if let drop = holeDrops.first { dropBanner(drop) }
                }
                .padding(.horizontal)
            }
            scoreEntry
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
                        .stroke(.white, lineWidth: 2)
                    Annotation("Target", coordinate: measurePoint.clCoordinate) {
                        VStack(spacing: 2) {
                            Text("\(Geo.yards(origin, measurePoint))").font(.caption.bold())
                            Circle().stroke(.white, lineWidth: 2).frame(width: 18, height: 18)
                            Text("\(Geo.yards(measurePoint, hole.greenCenter)) to pin").font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    }
                } else {
                    MapPolyline(coordinates: [origin.clCoordinate, hole.greenCenter.clCoordinate])
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }

                Annotation("Tee", coordinate: hole.tee.clCoordinate) {
                    Circle().fill(.white).frame(width: 10, height: 10)
                }
                Annotation("Pin", coordinate: hole.greenCenter.clCoordinate) {
                    Image(systemName: "flag.fill").foregroundStyle(.red).font(.title3).shadow(radius: 2)
                }
                ForEach(hole.hazards) { hazard in
                    Annotation(hazard.label, coordinate: hazard.near.clCoordinate) {
                        Circle()
                            .fill(hazard.kind == .water ? Color.blue : Color(red: 0.93, green: 0.85, blue: 0.62))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                    }
                }
                ForEach(holeDrops) { drop in
                    MapCircle(center: drop.center.clCoordinate, radius: drop.radiusMeters)
                        .foregroundStyle(Color.gimmeGold.opacity(0.2))
                        .stroke(Color.gimmeGold, lineWidth: 2)
                    Annotation(drop.brand, coordinate: Geo.offset(drop.center, meters: 25, bearing: hole.bearing + 90).clCoordinate) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(.black)
                            .padding(6)
                            .background(Color.gimmeGold, in: Circle())
                    }
                }
                if let me = location.coordinate {
                    Annotation("You", coordinate: me.clCoordinate) {
                        Circle().fill(.blue).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
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
        let middle = Geo.offset(hole.tee, meters: lengthMeters * 0.55, bearing: hole.bearing)
        camera = .camera(MapCamera(centerCoordinate: middle.clCoordinate,
                                   distance: max(lengthMeters * 2.4, 450),
                                   heading: hole.bearing,
                                   pitch: 0))
    }

    // MARK: Overlays

    private var distanceCard: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Hole \(hole.number)").font(.headline)
                Text("Par \(hole.par) · \(hole.lengthYards) yds").foregroundStyle(.secondary)
                Spacer()
                Button { app.goToHole(hole.number - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(hole.number == 1)
                Button { app.goToHole(hole.number + 1) } label: { Image(systemName: "chevron.right") }
            }
            HStack {
                yardage("Front", hole.greenFront)
                yardage("Middle", hole.greenCenter, big: true)
                yardage("Back", hole.greenBack)
            }
            if !hole.hazards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(hole.hazards) { hazard in
                            Text("\(hazard.label) \(Geo.yards(origin, hazard.near)) · carry \(Geo.yards(origin, hazard.carry))")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            if location.isSimulating || app.course?.id == DemoCourse.id {
                simulator
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 4)
    }

    private func yardage(_ label: String, _ point: Coordinate, big: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text("\(Geo.yards(origin, point))")
                .font(big ? .system(size: 40, weight: .bold, design: .rounded) : .title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Demo controls: jump your position around the hole to try distances and drops.
    private var simulator: some View {
        HStack {
            Text("Walk to").font(.caption).foregroundStyle(.secondary)
            Button("Tee") { location.simulate(hole.tee) }
            Button("Fairway") {
                location.simulate(Geo.offset(hole.tee, meters: Geo.meters(hole.tee, hole.greenCenter) * 0.6, bearing: hole.bearing))
            }
            Button("Green") { location.simulate(hole.greenFront) }
            Spacer()
        }
        .font(.caption.bold())
        .buttonStyle(.bordered)
    }

    private func dropBanner(_ drop: Drop) -> some View {
        HStack {
            Image(systemName: "gift.fill").foregroundStyle(Color.gimmeGold)
            VStack(alignment: .leading) {
                Text("\(drop.brand): \(drop.prize)").font(.subheadline.bold())
                Text(app.pendingChallenges.contains(drop.id) ? "Unlocked! \(drop.challenge.label)." : drop.challenge.label)
                    .font(.caption)
            }
            Spacer()
            Text("\(drop.remaining) left").font(.caption.bold())
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gimmeGold, lineWidth: 2))
    }

    // MARK: Scoring

    private var scoreEntry: some View {
        VStack(spacing: 6) {
            ForEach(app.round?.players ?? []) { player in
                let strokes = app.round?.strokes(player.id, hole: hole.number)
                HStack {
                    Text("\(player.avatar) \(player.name)").lineLimit(1)
                    Spacer()
                    if let strokes {
                        Text(Scoring.label(strokes: strokes, par: hole.par))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { app.setStrokes(max(1, (strokes ?? hole.par) - 1), for: player, hole: hole.number) } label: {
                        Image(systemName: "minus.circle.fill").font(.title2)
                    }
                    Text(strokes.map { "\($0)" } ?? "–")
                        .font(.title3.monospacedDigit().bold())
                        .frame(width: 32)
                    Button { app.setStrokes((strokes ?? hole.par - 1) + 1, for: player, hole: hole.number) } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.gimmeGreen)
            }
        }
        .padding()
        .background(.bar)
    }
}
