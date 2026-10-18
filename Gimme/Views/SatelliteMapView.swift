import MapKit
import Observation
import SwiftUI

/// Where the satellite photos come from. Set `SatelliteProvider` in Info.plist (project.yml).
///
/// - `apple`: Apple Maps imagery, no key, good in most places.
/// - `mapbox`: Mapbox Satellite, sharper and more recently refreshed in many US and European areas.
///   Needs `MapboxAccessToken` (free tier covers early users).
/// - `esri`: Esri World Imagery, often the sharpest (down to ~30 cm) on US courses. Fine for testing;
///   publishing an app on it needs an ArcGIS Location Platform key and their attribution.
///
/// No provider is live: every one shows photos that are months to a few years old. Courses that
/// change (new bunkers, rebuilt greens) still need their map data updated by hand.
enum ImageryProvider: String {
    case apple, mapbox, esri

    static var current: ImageryProvider {
        let configured = Bundle.main.object(forInfoDictionaryKey: "SatelliteProvider") as? String
        let provider = ImageryProvider(rawValue: configured?.lowercased() ?? "") ?? .apple
        if provider == .mapbox && mapboxToken.isEmpty { return .apple }
        return provider
    }

    private static var mapboxToken: String {
        Bundle.main.object(forInfoDictionaryKey: "MapboxAccessToken") as? String ?? ""
    }

    var tileTemplate: String? {
        switch self {
        case .apple: nil
        case .mapbox: "https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token=\(Self.mapboxToken)"
        case .esri: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        }
    }

    var attribution: String? {
        switch self {
        case .apple: nil
        case .mapbox: "© Mapbox © Maxar"
        case .esri: "Esri, Maxar, Earthstar Geographics"
        }
    }
}

/// Converts map coordinates to screen points so SwiftUI markers can sit on top of the map.
/// `revision` changes whenever the map moves, which redraws anything that reads it.
@MainActor
@Observable
final class MapProjector {
    private(set) var revision = 0
    @ObservationIgnored weak var mapView: MKMapView?

    func moved() { revision &+= 1 }

    func point(_ coordinate: Coordinate) -> CGPoint? {
        _ = revision
        guard let mapView else { return nil }
        return mapView.convert(coordinate.clCoordinate, toPointTo: mapView)
    }
}

/// A line drawn on the map.
struct MapLine: Hashable {
    var points: [Coordinate]
    var color: UIColor
    var width: CGFloat = 2.5
    var dashed = false
}

/// A filled circle on the map, such as a prize drop zone.
struct MapZone: Hashable {
    var center: Coordinate
    var radiusMeters: Double
    var color: UIColor
}

/// Satellite hole map: imagery from `ImageryProvider`, the camera turned so the hole plays up
/// the screen, lines and zones drawn by MapKit, and taps reported as coordinates.
struct SatelliteMapView: UIViewRepresentable {
    struct Frame: Equatable {
        var center: Coordinate
        var distance: Double
        var heading: Double
        /// Bump to move the camera back to this frame after the golfer has panned away.
        var revision = 0
    }

    /// Changing this moves the camera (once per hole or recenter, not on every redraw).
    var frame: Frame
    var lines: [MapLine] = []
    var zones: [MapZone] = []
    var projector: MapProjector
    var onTap: (Coordinate) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        map.isRotateEnabled = true
        if let template = ImageryProvider.current.tileTemplate {
            let tiles = MKTileOverlay(urlTemplate: template)
            tiles.tileSize = CGSize(width: 512, height: 512)
            tiles.maximumZ = 21
            tiles.canReplaceMapContent = true
            map.addOverlay(tiles, level: .aboveRoads)
        }
        map.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator,
                                                        action: #selector(Coordinator.tapped(_:))))
        projector.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastFrame != frame {
            context.coordinator.lastFrame = frame
            let camera = MKMapCamera(lookingAtCenter: frame.center.clCoordinate,
                                     fromDistance: frame.distance, pitch: 0, heading: frame.heading)
            map.setCamera(camera, animated: context.coordinator.hasFramed)
            context.coordinator.hasFramed = true
        }
        let drawn = context.coordinator.drawn
        if drawn.lines != lines || drawn.zones != zones {
            map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
            for line in lines {
                let polyline = StyledPolyline(coordinates: line.points.map(\.clCoordinate), count: line.points.count)
                polyline.style = line
                map.addOverlay(polyline, level: .aboveLabels)
            }
            for zone in zones {
                let circle = StyledCircle(center: zone.center.clCoordinate, radius: zone.radiusMeters)
                circle.color = zone.color
                map.addOverlay(circle, level: .aboveLabels)
            }
            context.coordinator.drawn = (lines, zones)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SatelliteMapView
        var lastFrame: Frame?
        var hasFramed = false
        var drawn: (lines: [MapLine], zones: [MapZone]) = ([], [])

        init(_ parent: SatelliteMapView) { self.parent = parent }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            parent.onTap(Coordinate(coordinate))
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            MainActor.assumeIsolated { parent.projector.moved() }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let line = overlay as? StyledPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.style.color
                renderer.lineWidth = line.style.width
                renderer.lineCap = .round
                if line.style.dashed { renderer.lineDashPattern = [6, 5] }
                return renderer
            }
            if let circle = overlay as? StyledCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = circle.color.withAlphaComponent(0.2)
                renderer.strokeColor = circle.color
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private final class StyledPolyline: MKPolyline {
    var style = MapLine(points: [], color: .white)
}

private final class StyledCircle: MKCircle {
    var color: UIColor = .systemYellow
}
