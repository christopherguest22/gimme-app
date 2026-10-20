import Observation
import SwiftUI
#if canImport(LiveKit)
import LiveKit
#endif

/// The camera stream for a live round, carried by LiveKit. The golfer who went live publishes
/// their camera and microphone; friends watching subscribe to it. Everything else about watching
/// (position, scores, cheers) works without it.
@MainActor
@Observable
final class LiveVideo {
    enum State: Equatable { case off, connecting, on, failed(String) }

    private(set) var state = State.off
    private(set) var micOn = true
    /// Bumped when the video track appears or goes away, so views redraw.
    private(set) var revision = 0

    #if canImport(LiveKit)
    @ObservationIgnored private(set) var track: VideoTrack?
    @ObservationIgnored private var room: Room?
    #endif
    @ObservationIgnored private var watcher: Task<Void, Never>?

    var hasVideo: Bool {
        _ = revision
        #if canImport(LiveKit)
        return track != nil
        #else
        return false
        #endif
    }

    func start(_ access: LiveVideoAccess, publish: Bool) async {
        #if canImport(LiveKit)
        guard room == nil else { return }
        state = .connecting
        let room = Room()
        self.room = room
        do {
            try await room.connect(url: access.url.absoluteString, token: access.token)
            // Closed while connecting: don't come back to life.
            guard self.room === room else {
                await room.disconnect()
                return
            }
            if publish {
                try await room.localParticipant.setCamera(enabled: true)
                try await room.localParticipant.setMicrophone(enabled: micOn)
            }
            state = .on
            // Picks up the camera track once it's flowing (and the host's, when they switch it on later).
            watcher = Task { [weak self] in
                while !Task.isCancelled {
                    let found: VideoTrack? = publish
                        ? room.localParticipant.firstCameraVideoTrack
                        : room.remoteParticipants.values.lazy.compactMap(\.firstCameraVideoTrack).first
                    guard let self else { return }
                    let foundId = found.map { ObjectIdentifier($0) }
                    if foundId != self.track.map({ ObjectIdentifier($0) }) {
                        self.track = found
                        self.revision &+= 1
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
            self.room = nil
        }
        #else
        state = .failed(LiveVideoError.notSetUp.localizedDescription)
        #endif
    }

    func toggleMic() async {
        micOn.toggle()
        #if canImport(LiveKit)
        _ = try? await room?.localParticipant.setMicrophone(enabled: micOn)
        #endif
    }

    func stop() async {
        watcher?.cancel()
        watcher = nil
        #if canImport(LiveKit)
        track = nil
        await room?.disconnect()
        room = nil
        #endif
        revision &+= 1
        state = .off
    }
}

/// Shows the live camera, filling its frame.
struct LiveVideoView: View {
    let video: LiveVideo
    var mirrored = false

    var body: some View {
        _ = video.revision
        #if canImport(LiveKit)
        if let track = video.track {
            return AnyView(TrackView(track: track, mirrored: mirrored))
        }
        #endif
        return AnyView(Color.black)
    }
}

#if canImport(LiveKit)
private struct TrackView: UIViewRepresentable {
    let track: VideoTrack
    var mirrored: Bool

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fill
        view.mirrorMode = mirrored ? .mirror : .off
        view.track = track
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {
        if view.track.map({ ObjectIdentifier($0) }) != ObjectIdentifier(track) { view.track = track }
    }
}
#endif
