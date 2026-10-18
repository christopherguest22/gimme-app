# Gimme (iPhone starter app)

A first build of Gimme in SwiftUI: GPS distances on every hole, a live group scorecard and chat, a friends feed, and brand prize drops that unlock by geofence on a hole, with a prize wallet.

It runs fully offline on a built-in **mock backend** with sample friends and four sample brand drops, so you can try everything in the Simulator before setting up any accounts.

## Open it in Xcode

You need a Mac with Xcode 15 or newer (iOS 17 SDK).

**Option A: XcodeGen (quickest)**

1. Copy this `gimme-app` folder to your Mac.
2. In Terminal: `brew install xcodegen`, then `cd gimme-app && xcodegen`.
3. Open the new `Gimme.xcodeproj`.
4. Select the **Gimme** target, open **Signing & Capabilities**, and pick your Apple ID team.
5. Choose an iPhone simulator and press **Run** (⌘R). Press ⌘U to run the tests.

**Option B: without XcodeGen**

1. In Xcode: **File › New › Project › iOS App**, name it `Gimme`, interface SwiftUI, minimum iOS 17.
2. Delete the generated `ContentView.swift` and `GimmeApp.swift`.
3. Drag the `Gimme/App`, `Gimme/Models`, `Gimme/Services` and `Gimme/Views` folders into the project ("Copy items if needed", target Gimme).
4. In the target's **Info** tab add `Privacy - Location When In Use Usage Description` with a sentence like "Gimme uses your location for distances and prize drops."
5. Run.

## Try a round

1. Allow location when asked. In the Simulator, pick **Features › Location › Apple** (or any spot).
2. **Home › Start a round**, tick a couple of friends, and choose **Gimme Demo Links**. This is a made-up 18-hole layout that starts wherever you are standing, so you can test anywhere.
3. On the **Round** tab you'll see the satellite hole map with front, middle and back yardages, hazards, and your position. Tap anywhere on the map to measure to that spot and from there to the pin.
4. Use the **Walk to Tee / Fairway / Green** buttons to move yourself around the hole.
5. Holes **3, 7, 12 and 16** have gold-flag drops. Walk to the green on hole 3 and the "You found a drop!" screen appears. Holes 7 and 12 need par or birdie: walk to the green, then enter your score.
6. Prizes land in the **Prizes** tab. Finish the round to post it to the **Friends** feed and your **Profile** history.

**Courses near you** loads real course maps from OpenStreetMap. Many courses have their holes mapped there, but not all.

## How the code is laid out

| Folder | What's inside |
|---|---|
| `Gimme/App` | App entry, tabs, and `AppState` (round, friends, drops, wallet) |
| `Gimme/Models` | Course, hole, round, drop and feed types; GPS math (`Geo.swift`); scoring and handicap estimate |
| `Gimme/Services` | `LocationService` (CoreLocation), `CourseService` (OpenStreetMap course maps), `DemoCourse`, `Backend` (protocol plus the offline `MockBackend`) |
| `Gimme/Views` | Home, Hole (GPS map), Scorecard, Round chat, Feed, Prize wallet, Drop found, Profile |
| `GimmeTests` | Unit tests for distances, scoring, handicap and the drop claim rules |
| `supabase/schema.sql` | The real backend: tables, privacy rules, live updates for scores and chat, and server-side drop claim checks |

## Going live with Supabase

1. Create a free project at supabase.com and run `supabase/schema.sql` in its SQL editor.
2. Add the `supabase-swift` package in Xcode and write a `SupabaseBackend` that implements the `GimmeBackend` protocol in `Services/Backend.swift`.
3. Pass it in `GimmeApp.swift`: `AppState(backend: SupabaseBackend(...))`.

Drop claims go through two server functions: `visit_drop` (the phone's position is inside the hole's geofence during an active round) and `claim_drop` (stock left, one per golfer, challenge met). The schema was run and tested against Postgres 16.

## What's not done yet

- The Swift code was written without a Mac, so it has not been compiled yet. Expect a few small fixes on the first build in Xcode.
- No sign-in; the mock backend uses sample data.
- Drops unlock while the app is open. Background unlocks (`CLMonitor` region monitoring) and push alerts come next.
- Side games (skins, Nassau), leagues, shot tracking, Apple Watch and the brand dashboard are later phases from the product plan.
- Course maps from OpenStreetMap need an on-screen "© OpenStreetMap contributors" credit (already shown when choosing a course).
