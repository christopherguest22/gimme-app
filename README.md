# Gimme (iPhone app)

Gimme puts three things in one app: GPS distances on every hole, a live scorecard and chat for your group, and prizes from golf brands that unlock when you reach a hole.

| Folder | What it is |
|---|---|
| `Gimme/` | The iPhone app (SwiftUI, iOS 17+) |
| `GimmeTests/` | Unit tests for distances, scoring, side games and drop rules |
| `supabase/schema.sql` | The backend database: accounts, friends, rounds, live scores and chat, drops, brands |
| `brand-dashboard/index.html` | A web page brands use to place drops, see results and redeem codes |
| `project.yml` | Builds the Xcode project with XcodeGen |

## What's in the app

The look and navigation follow 18Birdies (dark, map-first, a raised Play button in the middle of the tab bar) with Gimme's own colors, icons and names. No 18Birdies code or artwork is used.

Tabs along the bottom: **Home, Community, Play, Prizes, Me.**

- **Welcome and sign-in:** three intro slides, then sign-in with a 6-digit email code. In demo mode you only pick a name and avatar.
- **Home:** a big Play or Resume card, your handicap, rounds and prizes, friends on the course now, and prize drops near you.
- **Play (center button):** pick a course, then the hole fills the screen. Front, middle and back yardages sit on the right, hazard distances sit on the map, and tap-to-measure shows distance to a target and to the pin. The bottom panel switches holes and keeps score for everyone with plus and minus buttons. Holes with a prize drop show a gold zone around the green. While a round is running the Play button turns gold and says Resume.
- **Live scorecard and chat:** buttons at the top of the hole screen. Scores update live from everyone's phones, birdies circled in gold and bogeys boxed, with skins and Nassau below. Chat is for your group during the round.
- **Prize drops:** reach the gold zone during a round and the prize unlocks. Some drops need par or birdie first. GPS keeps running with the phone in your pocket, and you get a notification when you win.
- **Prizes:** won prizes with copyable codes, expiry dates and redeemed status.
- **Community:** Feed (rounds, prizes and posts), Leaderboard (friends by handicap) and Friends (add by handle).
- **Me:** profile header with handicap, rounds, friends and prizes, your stats, and round history (tap a round for its scorecard). Edit profile and sign out are in the menu.

## Website

`website/index.html` is the Gimme marketing site, laid out like 18birdies.com: top menu, a hero with the App Store button, a section each for GPS, scoring, community and prizes, a "For brands" section that links to the brand dashboard, and a footer. Reviews and the App Store link are placeholders until launch. Open the file in a browser, or host the `website` folder on any static host.

## Open it in Xcode

You need a Mac with Xcode 15 or newer.

1. Copy the `gimme-app` folder to your Mac.
2. In Terminal: `brew install xcodegen`, then `cd gimme-app && xcodegen`.
3. Open `Gimme.xcodeproj`. Xcode downloads the Supabase package the first time.
4. Select the **Gimme** target › **Signing & Capabilities** › pick your Apple ID team.
5. Choose an iPhone simulator and press **Run** (⌘R). ⌘U runs the tests.

The app starts in **demo mode**: sample friends, sample sponsors, and friends who "play along" so their scores show up on your card a few seconds after yours.

### Try a round in the Simulator

1. Allow location. In the Simulator menu choose **Features › Location › Apple**.
2. **Start a round**, tick a couple of friends, and pick **Gimme Demo Links**. That practice course builds itself wherever you're standing.
3. Use **Walk to Tee / Fairway / Green** to move around the hole. Tap the map to measure.
4. Holes **3, 7, 12 and 16** have drops. Walk to the green on hole 3 to win one. Holes 7 and 12 need par or birdie, so walk to the green and then enter your score.
5. **Courses near you** loads real course maps from OpenStreetMap, where volunteers have mapped the holes.

## Turn on the real backend (Supabase, free tier)

1. Create a project at supabase.com.
2. In **SQL Editor**, paste and run `supabase/schema.sql`.
3. In **Authentication › Email Templates › Magic Link**, add `{{ .Token }}` to the email so golfers get a 6-digit code.
4. In **Project Settings › API**, copy the Project URL and the `anon` public key into `SupabaseURL` and `SupabaseAnonKey` in `project.yml`, then run `xcodegen` again.

The app switches from demo data to the real backend as soon as those two values are filled in. Prize rules are enforced on the server: `visit_drop` checks the golfer is inside the zone during an active round, and `claim_drop` checks stock, one claim per golfer and the hole challenge.

## Brand dashboard

Open `brand-dashboard/index.html` in a browser. With no keys it runs on demo data. To use real data, put the same Supabase URL and anon key at the top of the file and host it anywhere static (Netlify, Vercel, GitHub Pages, Supabase Storage).

To give a brand access, add a row to `brands` and a row to `brand_members` (their user id) in the Supabase table editor. They sign in with their email and can:

- place a drop on any course and hole golfers have played, with a prize, quantity, dates, unlock zone size and challenge;
- see golfers reached, prizes claimed and codes redeemed per drop;
- mark a code as used at the counter.

## What was tested, and what wasn't

- The database was run on Postgres 16 as signed-in users, with Supabase-style row security. These all passed: adding friends, live score visibility, unlock-zone checks, par challenges, one claim per golfer, brand-only drop creation, brand stats, and redeeming codes.
- The brand dashboard was run in a headless browser in demo mode with no errors.
- The Swift code has **not** been compiled, because iPhone apps need a Mac to build. Expect a few small fixes on the first build. The Supabase part (`SupabaseBackend.swift`) is the most likely to need tweaks, since it targets supabase-swift 2.x.

## Next up

- Handicap strokes in skins and Nassau, and leagues and season standings.
- Shot tracking with club selection, and an Apple Watch app.
- Push notifications from the server (a friend's birdie, a new drop at your course).
- A licensed course-data provider for courses OpenStreetMap doesn't cover.
- Legal review of prize drops (sweepstakes rules vary by state) before launch.
