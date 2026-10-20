import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Community, TikTok meets LinkedIn: a full-screen feed you swipe up through (clips from the
/// course, prizes won, rounds, friends going live), each post carrying the golfer's card the
/// way LinkedIn does (handicap, home course, connect), plus a Network page for your people.
struct CommunityView: View {
    @Environment(AppState.self) private var app
    @State private var pane = Pane.forYou
    @State private var composing = false
    @State private var watching: LiveTarget?

    enum Pane: String, CaseIterable { case forYou = "For You", following = "Following", network = "Network" }

    private var posts: [FeedPost] {
        switch pane {
        case .forYou:
            return Trending.forYou(stillRelevant)
        case .following:
            let friends = Set(app.friends.map(\.id))
            return stillRelevant.filter { friends.contains($0.author.id) || $0.author.id == app.myId }
        case .network:
            return []
        }
    }

    private var liveFriends: [Player] { app.friends.filter { $0.liveRoundId != nil } }

    /// Live posts drop out once the round stops being live.
    private var stillRelevant: [FeedPost] {
        app.feed.filter { post in
            guard post.kind == .live else { return true }
            if post.author.id == app.myId { return app.isLive && app.round?.id == post.roundId }
            return app.friends.contains { $0.id == post.author.id && $0.liveRoundId == post.roundId }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if pane == .network {
                NetworkView(watch: { watching = LiveTarget(id: $0) })
                    .padding(.top, 52)
            } else if posts.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "video",
                                       description: Text("Clips, prizes and rounds from golfers you follow show up here."))
            } else {
                FeedPager(posts: posts, watch: { watching = LiveTarget(id: $0) })
                    .id(pane)
            }
            header
        }
        .sheet(isPresented: $composing) { NewClipSheet() }
        .fullScreenCover(item: $watching) { LiveRoundView(roundId: $0.id) }
        .task { await app.load() }
    }

    /// TikTok-style text tabs over the video, with LIVE on the left and a post button on the right.
    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if let first = liveFriends.first?.liveRoundId { watching = LiveTarget(id: first) }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(liveFriends.isEmpty ? Color.white.opacity(0.4) : Color.gimmeBirdie).frame(width: 7, height: 7)
                    Text("LIVE").font(.gimme(12, .heavy))
                    if liveFriends.count > 1 { Text("\(liveFriends.count)").font(.gimme(12, .heavy)) }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
            }
            .disabled(liveFriends.isEmpty)
            .accessibilityLabel(liveFriends.isEmpty ? "No friends live" : "Watch a friend live")
            Spacer(minLength: 0)
            ForEach(Pane.allCases, id: \.self) { item in
                Button { withAnimation(.snappy) { pane = item } } label: {
                    VStack(spacing: 4) {
                        Text(item.rawValue).font(.gimme(16, pane == item ? .heavy : .bold))
                            .opacity(pane == item ? 1 : 0.65)
                        Capsule().fill(.white).frame(width: 22, height: 3).opacity(pane == item ? 1 : 0)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { composing = true } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(Color.gimmeLime, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.black)
            }
            .accessibilityLabel("Post a clip")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

/// A live round to open full screen.
struct LiveTarget: Identifiable {
    let id: UUID
}

// MARK: - Pager

/// Full-screen posts, one per swipe.
struct FeedPager: View {
    @Environment(AppState.self) private var app
    let posts: [FeedPost]
    var watch: (UUID) -> Void
    @State private var current: UUID?
    @State private var commenting: FeedPost?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    FeedPage(post: app.feed.first { $0.id == post.id } ?? post,
                             isCurrent: current == post.id,
                             watch: watch,
                             comment: { commenting = $0 })
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(post.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .onAppear { if current == nil { current = posts.first?.id } }
        .onChange(of: current) { _, id in
            if let post = posts.first(where: { $0.id == id }) { app.viewed(post) }
        }
        .sheet(item: $commenting) { CommentsSheet(post: $0) }
    }
}

/// One post, full screen: the video (or the post's card) behind, the golfer's card and caption
/// along the bottom, and reactions down the right side.
struct FeedPage: View {
    @Environment(AppState.self) private var app
    let post: FeedPost
    var isCurrent: Bool
    var watch: (UUID) -> Void
    var comment: (FeedPost) -> Void
    @State private var reporting: ReportTarget?

    var body: some View {
        ZStack(alignment: .bottom) {
            background
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 12) {
                caption
                Spacer(minLength: 0)
                rail
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 92)
        }
        .foregroundStyle(.white)
        .clipped()
        .reportDialog($reporting)
    }

    // MARK: Background

    @ViewBuilder private var background: some View {
        switch post.kind {
        case .clip:
            if let url = post.videoURL {
                LoopingVideo(url: url, playing: isCurrent)
            } else {
                HolePoster(post: post)
            }
        case .trending:
            if let clip = app.feed.first(where: { $0.id == post.refPostId }), let url = clip.videoURL {
                LoopingVideo(url: url, playing: isCurrent).overlay { Color.black.opacity(0.35) }
            } else {
                HolePoster(post: post)
            }
        case .drop:
            PrizePoster(post: post)
        case .live:
            LivePoster(post: post, watch: watch)
        case .round, .note:
            TextPoster(post: post)
        }
    }

    // MARK: Caption (the LinkedIn part)

    private var caption: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                AvatarView(player: post.author, size: 40)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(post.author.name).font(.gimme(16, .heavy))
                        connectBadge
                    }
                    if !post.author.headline.isEmpty {
                        Text(post.author.headline).font(.gimme(12, .bold)).opacity(0.85)
                    }
                }
            }
            kindLabel
            Text(post.title).font(.gimme(17, .heavy)).lineLimit(3)
            if !post.detail.isEmpty {
                Text(post.detail).font(.gimme(14, .semibold)).opacity(0.92).lineLimit(3)
            }
            HStack(spacing: 8) {
                if let tag = post.holeTag {
                    Label(tag, systemImage: "flag.fill")
                        .font(.gimme(12, .heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                Text(post.postedAt, format: .relative(presentation: .named)).font(.gimme(12, .bold)).opacity(0.75)
            }
            if post.kind == .drop || post.kind == .round, post.author.id != app.myId {
                Button { app.toggle(.congrats, on: post) } label: {
                    Label(post.congratsByMe ? "Congratulated" : "Congratulate \(post.author.name)",
                          systemImage: "hands.clap.fill")
                        .font(.gimme(14, .heavy))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(post.congratsByMe ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(LinearGradient.gimmePrize),
                                    in: Capsule())
                        .foregroundStyle(post.congratsByMe ? .white : .black)
                }
                .padding(.top, 2)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 3)
    }

    @ViewBuilder private var connectBadge: some View {
        if post.author.id == app.myId {
            EmptyView()
        } else if app.friends.contains(where: { $0.id == post.author.id }) {
            Text("Friends").font(.gimme(11, .heavy))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
        } else {
            Button { Task { await app.addFriend(post.author.handle ?? post.author.name) } } label: {
                Text("+ Connect").font(.gimme(11, .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.gimmeLime, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
    }

    @ViewBuilder private var kindLabel: some View {
        switch post.kind {
        case .trending:
            Label("Trending hole", systemImage: "flame.fill").font(.gimme(12, .heavy)).foregroundStyle(Color.orange)
        case .drop:
            Label("Prize drop won", systemImage: "gift.fill").font(.gimme(12, .heavy)).foregroundStyle(Color.gimmeGold)
        case .live:
            Label("Live round", systemImage: "dot.radiowaves.left.and.right").font(.gimme(12, .heavy)).foregroundStyle(Color.gimmeBirdie)
        default:
            EmptyView()
        }
    }

    // MARK: Rail (the TikTok part)

    private var rail: some View {
        VStack(spacing: 18) {
            moreMenu
            railButton(post.likedByMe ? "heart.fill" : "heart", count: post.likes, tint: post.likedByMe ? Color.gimmeBirdie : .white,
                       label: "Like") { app.toggle(.like, on: post) }
            railButton("bubble.right.fill", count: post.comments, label: "Comments") { comment(post) }
            if post.kind == .drop || post.kind == .round {
                railButton("hands.clap.fill", count: post.congrats, tint: post.congratsByMe ? Color.gimmeGold : .white,
                           label: "Congrats") { app.toggle(.congrats, on: post) }
            }
            if post.kind == .clip {
                VStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                    Text(post.views.formatted(.number.notation(.compactName))).font(.gimme(12, .heavy))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(post.views) views")
            }
            ShareLink(item: shareText) {
                VStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.right.fill").font(.system(size: 24, weight: .bold))
                    Text("Share").font(.gimme(12, .heavy))
                }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
        .frame(width: 56)
    }

    /// Report, block, or delete your own post.
    private var moreMenu: some View {
        Menu {
            if post.author.id == app.myId {
                Button("Delete post", systemImage: "trash", role: .destructive) { Task { await app.deletePost(post) } }
            } else {
                Button("Report post", systemImage: "flag") { reporting = .post(post) }
                Button("Block \(post.author.name)", systemImage: "hand.raised", role: .destructive) {
                    Task { await app.block(post.author) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 22, weight: .heavy))
                .frame(width: 44, height: 32)
        }
        .accessibilityLabel("More options")
    }

    private var shareText: String {
        [post.title, post.holeTag, post.videoURL?.scheme == "https" ? post.videoURL?.absoluteString : nil, "on Gimme"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func railButton(_ icon: String, count: Int, tint: Color = .white, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 28, weight: .bold)).foregroundStyle(tint)
                Text(count.formatted(.number.notation(.compactName))).font(.gimme(12, .heavy))
            }
        }
        .accessibilityLabel("\(label), \(count)")
    }
}

// MARK: - Posters for posts without video

/// The hole on satellite, when the course's map is loaded; otherwise a fairway gradient.
struct HolePoster: View {
    @Environment(AppState.self) private var app
    let post: FeedPost
    @State private var projector = MapProjector()

    private var hole: Hole? {
        guard let id = post.courseId, let number = post.hole else { return nil }
        let course = app.course?.id == id ? app.course : app.previewCourses[id]
        return course?.hole(number)
    }

    var body: some View {
        ZStack {
            if let hole {
                let length = Geo.meters(hole.tee, hole.greenCenter)
                SatelliteMapView(frame: .init(center: Geo.offset(hole.tee, meters: length * 0.55, bearing: hole.bearing),
                                              distance: max(length * 2.0, 380), heading: hole.bearing),
                                 lines: [MapLine(points: [hole.tee, hole.greenCenter], color: UIColor(Color.gimmeGold), width: 3)],
                                 projector: projector)
                    .allowsHitTesting(false)
            } else {
                LinearGradient.gimmeFairway
            }
            if post.kind == .clip {
                Image(systemName: "play.circle.fill").font(.system(size: 64)).opacity(0.85)
            }
        }
        .task {
            if let id = post.courseId, let pack = CoursePack.course(id: id) { await app.loadPreview(pack) }
        }
    }
}

/// A prize won: the product big in the middle, LinkedIn-achievement style.
struct PrizePoster: View {
    let post: FeedPost

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.gimmeDeepGreen, .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient.gimmePrize).frame(width: 236, height: 236)
                    Circle().fill(Color(white: 0.97)).frame(width: 214, height: 214)
                    if let url = post.imageURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 168, height: 168)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "gift.fill").font(.system(size: 80)).foregroundStyle(Color.gimmeGold)
                    }
                }
                Text("PRIZE DROP").font(.gimme(13, .heavy)).tracking(2).foregroundStyle(Color.gimmeGold)
            }
            .padding(.bottom, 180)
        }
    }
}

/// A friend's live round: tap in to watch.
struct LivePoster: View {
    let post: FeedPost
    var watch: (UUID) -> Void
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.35, green: 0.04, blue: 0.06), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.gimmeBirdie, lineWidth: 4).frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.15 : 0.95).opacity(pulse ? 0.2 : 0.9)
                    AvatarView(player: post.author, size: 120)
                }
                Text("LIVE").font(.gimme(14, .heavy)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.gimmeBirdie, in: Capsule())
                if let roundId = post.roundId {
                    Button { watch(roundId) } label: {
                        Label("Watch the round", systemImage: "play.fill")
                    }
                    .buttonStyle(.gimmePrize)
                    .frame(width: 240)
                }
            }
            .padding(.bottom, 160)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Rounds and notes: the words big on a fairway backdrop.
struct TextPoster: View {
    let post: FeedPost

    var body: some View {
        ZStack {
            LinearGradient.gimmeFairway
            Image(systemName: post.icon).font(.system(size: 90, weight: .bold)).opacity(0.18)
                .padding(.bottom, 200)
        }
    }
}

// MARK: - Video

/// A muted-by-default, looping, full-bleed video that plays only while its page is on screen.
struct LoopingVideo: UIViewRepresentable {
    let url: URL
    var playing: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if playing { view.playerLayer.player?.play() } else { view.playerLayer.player?.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: Coordinator) {
        view.playerLayer.player?.pause()
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var looper: AVPlayerLooper? }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Comments

struct CommentsSheet: View {
    @Environment(AppState.self) private var app
    let post: FeedPost
    @State private var comments: [FeedComment] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var reporting: ReportTarget?

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                if !loading && comments.isEmpty {
                    Text("No comments yet. Say something nice.").foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        AvatarView(player: comment.author, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(comment.author.name).font(.gimme(14, .heavy))
                                Text(comment.postedAt, format: .relative(presentation: .named))
                                    .font(.gimme(11)).foregroundStyle(.secondary)
                            }
                            Text(comment.text).font(.gimme(15))
                        }
                    }
                    .swipeActions {
                        if comment.author.id == app.myId {
                            Button("Delete", role: .destructive) {
                                Task {
                                    if await app.deleteComment(comment, on: post) { comments.removeAll { $0.id == comment.id } }
                                }
                            }
                        } else {
                            Button("Report") { reporting = .comment(comment) }.tint(.orange)
                            Button("Block", role: .destructive) {
                                Task {
                                    await app.block(comment.author)
                                    comments.removeAll { $0.author.id == comment.author.id }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Add a comment", text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {
                        let text = draft
                        draft = ""
                        Task { if let new = await app.comment(text, on: post) { comments.append(new) } }
                    }
                    .font(.gimme(15, .heavy))
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("\(post.comments) comments")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .reportDialog($reporting) { target in
            if case .comment(let reported) = target { comments.removeAll { $0.id == reported.id } }
        }
        .task {
            comments = await app.comments(on: post)
            loading = false
        }
    }
}

// MARK: - Posting a clip

/// Film a shot (or pick one from Photos), add a caption, and post it. During a round the clip
/// is tagged with the hole, which is how it can trend there.
struct NewClipSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var caption = ""
    @State private var audience = FeedPost.Audience.everyone
    @State private var recording = false
    @State private var picked: PhotosPickerItem?
    @State private var posting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let file {
                        LoopingVideo(url: file, playing: true)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .listRowInsets(EdgeInsets())
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { recording = true } label: { Label(file == nil ? "Film a shot" : "Film again", systemImage: "video.fill") }
                    }
                    PhotosPicker(selection: $picked, matching: .videos) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                }
                Section {
                    TextField("What happened?", text: $caption, axis: .vertical)
                    Picker("Who can see it", selection: $audience) {
                        Text("Everyone").tag(FeedPost.Audience.everyone)
                        Text("Friends").tag(FeedPost.Audience.friends)
                    }
                } footer: {
                    if app.round != nil, let course = app.course {
                        Text("Tagged #\(app.currentHole) at \(course.name). Clips with the most likes trend on their hole for everyone who plays it.")
                    }
                }
            }
            .navigationTitle("New clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if posting {
                        ProgressView()
                    } else {
                        Button("Post") {
                            guard let file else { return }
                            posting = true
                            Task {
                                if await app.postClip(file, caption: caption, audience: audience) { dismiss() }
                                posting = false
                            }
                        }
                        .disabled(file == nil)
                    }
                }
            }
            .fullScreenCover(isPresented: $recording) {
                VideoRecorder { url in file = url }.ignoresSafeArea()
            }
            .onChange(of: picked) { _, item in
                Task {
                    if let movie = try? await item?.loadTransferable(type: PickedMovie.self) { file = movie.url }
                }
            }
        }
    }
}

/// A video picked from Photos, copied somewhere the app can read it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// The system camera, set to video, up to a minute.
struct VideoRecorder: UIViewControllerRepresentable {
    var onRecorded: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = 60
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoRecorder
        init(_ parent: VideoRecorder) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { parent.onRecorded(url) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Network (the LinkedIn part)

/// Your card, friends live now, the handicap leaderboard, and your friends.
struct NetworkView: View {
    @Environment(AppState.self) private var app
    var watch: (UUID) -> Void
    @State private var addingFriend = false
    @State private var handle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let me = app.me { myCard(me) }

                let live = app.friends.filter { $0.liveRoundId != nil }
                if !live.isEmpty {
                    SectionHeader(title: "Live now")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(live) { friend in
                                Button { if let id = friend.liveRoundId { watch(id) } } label: {
                                    VStack(spacing: 6) {
                                        AvatarView(player: friend, size: 62)
                                            .overlay(Circle().stroke(Color.gimmeBirdie, lineWidth: 3).padding(-4))
                                            .overlay(alignment: .bottom) {
                                                Text("LIVE").font(.gimme(10, .heavy))
                                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.gimmeBirdie, in: Capsule())
                                                    .offset(y: 8)
                                            }
                                        Text(friend.name).font(.gimme(13, .bold)).padding(.top, 4)
                                    }
                                }
                                .foregroundStyle(.white)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                SectionHeader(title: "Handicap leaderboard")
                leaderboard

                SectionHeader(title: "Your network", action: ("Add", { addingFriend = true }))
                ForEach(app.friends) { friend in
                    HStack(spacing: 12) {
                        AvatarView(player: friend, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.name).font(.gimme(16, .heavy))
                            if !friend.headline.isEmpty {
                                Text(friend.headline).font(.gimme(13)).foregroundStyle(.secondary)
                            }
                            if let playing = friend.playingNow {
                                Text(playing).font(.gimme(12, .bold)).foregroundStyle(Color.gimmeLime)
                            }
                        }
                        Spacer()
                        if let id = friend.liveRoundId {
                            Button("Watch") { watch(id) }
                                .font(.gimme(13, .heavy))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.gimmeBirdie, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .gimmeCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await app.load() }
        .alert("Add a friend", isPresented: $addingFriend) {
            TextField("Their Gimme handle", text: $handle)
                .textInputAutocapitalization(.never)
            Button("Add") {
                let name = handle
                handle = ""
                Task { await app.addFriend(name) }
            }
            Button("Cancel", role: .cancel) { handle = "" }
        } message: {
            Text("Your friend's handle is on their Me tab.")
        }
    }

    /// Your profile card, LinkedIn style: who you are in golf, at a glance.
    private func myCard(_ me: Player) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient.gimmeFairway.frame(height: 56)
            VStack(alignment: .leading, spacing: 6) {
                AvatarView(player: me, size: 68)
                    .overlay(Circle().stroke(Color.gimmeSurface, lineWidth: 4))
                    .padding(.top, -38)
                Text(me.name).font(.gimme(22, .heavy))
                Text([app.handicapEstimate.map { String(format: "%.1f HCP", $0) }, me.homeCourse ?? "Add your home course in Edit profile"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.gimme(14, .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    stat("\(app.friends.count)", "Connections")
                    stat("\(app.pastRounds.count)", "Rounds")
                    stat("\(app.wallet.count)", "Prizes")
                    stat("\(app.feed.filter { $0.author.id == me.id && $0.kind == .clip }.count)", "Clips")
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(Color.gimmeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.gimme(17, .heavy))
            Text(label).font(.gimme(11, .bold)).foregroundStyle(.secondary)
        }
    }

    private var leaderboard: some View {
        var players = app.friends
        if var you = app.me {
            you.handicap = app.handicapEstimate ?? you.handicap
            players.append(you)
        }
        let ranked = players.sorted { ($0.handicap ?? 99) < ($1.handicap ?? 99) }
        return VStack(spacing: 0) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    Text("\(index + 1)").font(.gimme(16, .heavy))
                        .foregroundStyle(index == 0 ? Color.gimmeGold : .secondary)
                        .frame(width: 26)
                    AvatarView(player: player, size: 34)
                    Text(player.id == app.myId ? "\(player.name) (you)" : player.name).font(.gimme(15, .bold))
                    Spacer()
                    Text(player.handicap.map { String(format: "%.1f", $0) } ?? "–").font(.gimme(18, .heavy))
                }
                .padding(.vertical, 9)
                if index < ranked.count - 1 { Divider() }
            }
        }
        .gimmeCard()
    }
}

// MARK: - Reporting

extension View {
    /// Asks why a post, comment or golfer is being reported, then sends the report.
    func reportDialog(_ target: Binding<ReportTarget?>, reported: @escaping (ReportTarget) -> Void = { _ in }) -> some View {
        modifier(ReportDialog(target: target, reported: reported))
    }
}

private struct ReportDialog: ViewModifier {
    @Environment(AppState.self) private var app
    @Binding var target: ReportTarget?
    var reported: (ReportTarget) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Why are you reporting this?", isPresented: Binding(
            get: { target != nil }, set: { if !$0 { target = nil } }), titleVisibility: .visible, presenting: target) { item in
            ForEach(ReportTarget.reasons, id: \.self) { reason in
                Button(reason) {
                    reported(item)
                    Task { await app.report(item, reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("We review every report within 24 hours. You can also block them so you never see each other's posts.")
        }
    }
}
