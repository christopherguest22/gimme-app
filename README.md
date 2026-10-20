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
- **Play (center button):** pick a course and your tees, then the hole fills the screen as a satellite photo, laid out like 18Birdies. Across the top: hole number, distance to the hole, par, your tee's yardage and the hole's handicap (stroke index). On the right: the distance in a black circle with the plays-like yardage and a club next to it, a Green tile (back, middle, front), a Wind tile (arrow turned to the hole) and Tools (change tees, undo a shot, finish the round). On the left: Recenter, Scorecard and Group. Tap the map to set a target and see both legs of the shot. Along the bottom: previous hole, Track Shot (marks where each shot was hit and how far it went), Enter Score and the next hole. While a round is running the Play button turns gold and says Resume.
- **Live scorecard and chat:** buttons at the top of the hole screen. Scores update live from everyone's phones, birdies circled in gold and bogeys boxed, with skins and Nassau below. Chat is for your group during the round.
- **Prize drops:** reach the gold zone during a round and the prize unlocks. Some drops need par or birdie first. GPS keeps running with the phone in your pocket, and you get a notification when you win.
- **Prizes:** won prizes with copyable codes, expiry dates and redeemed status.
- **Community:** Feed (rounds, prizes and posts), Leaderboard (friends by handicap) and Friends (add by handle).
- **Me:** profile header with handicap, rounds, friends and prizes, your stats, and round history (tap a round for its scorecard). Edit profile and sign out are in the menu.

## Satellite imagery and course data

**Imagery.** Set `SatelliteProvider` in `project.yml`, then run `xcodegen` again:

- `apple` (default): Apple Maps satellite photos. No key.
- `mapbox`: Mapbox Satellite. Often sharper and more recently refreshed in many US and European areas. Create a free token at mapbox.com and paste it into `MapboxAccessToken`.
- `esri`: Esri World Imagery. Often the sharpest on US courses (down to about 30 cm per pixel). Fine for testing; a published app needs an ArcGIS Location Platform key and their credit line.

No provider shows live photos: all of them are months to a few years old, and that is true for 18Birdies too. Compare a few of your home courses on each provider and keep the sharpest.

**Kiawah Island photos built into the app.** For the launch courses the app carries its own aerial photos (`Gimme/Resources/kiawah-imagery.mbtiles`, 28 MB). NOAA's National Geodetic Survey flew the coast in 2026; the photos show about 30 cm per pixel and are public domain. They cover every golf hole on the island, draw on top of whichever provider is set above, and work with no phone signal on the course. To rebuild them, or make a pack for another area, see `tools/imagery/` (`prepare_area.py`, then `make_tiles.py`). `design/ocean-course-hole-18.jpg` is hole 18 of the Ocean Course cut from these photos.

**Hole data.** Each course is put together from three free sources:

- **Hole shapes** (tees, greens, bunkers, water) come from OpenStreetMap.
- **The scorecard** (par, handicap, yardage for every tee, rating and slope) comes from OpenGolfAPI. It covers about 16,000 US courses, needs no key and is ODbL licensed, so the app credits it. If OpenStreetMap hasn't mapped a course's holes but OpenGolfAPI has tee and green positions, the holes are built from OpenGolfAPI.
- **Elevation, wind and temperature** come from Open-Meteo. It is free for non-commercial use; a paid plan is needed once the app makes money.

**Plays-like distance** uses the rules of thumb 18Birdies describes: a yard longer for each yard uphill, 1% longer per mph of headwind and 0.5% shorter per mph of tailwind, and 2 yards for every 10°F away from 75°F on a 150-yard shot. The suggested club uses typical amateur distances in `Bag.standard` for now.

## Kiawah Island launch courses

For testing and launch, seven Kiawah Island courses ship inside the app (`Gimme/Resources/kiawah-courses.json`) and sit at the top of the course list: **The Ocean Course** (featured), Turtle Point, Cougar Point, Osprey Point, Oak Point, Cassique and The River Course (Cassique and River are marked members only).

- **Home** shows a featured card with hole 18 of the Ocean Course on satellite, with par, yardage and handicap.
- **Scorecards** (par, handicap, yardage for every tee, rating and slope) come from OpenGolfAPI and were checked so each tee's hole yardages add up to its total. Tees that didn't add up were left out: Red at Cassique, and White and Green at the River Course. Oak Point's public listing has every hole as par 5, so its holes come from the map only until a real card is added.
- **Hole positions** load from OpenStreetMap on the phone. If a course isn't mapped there, Gimme lays the holes out from the scorecard as a stand-in and shows a banner. Walking the course, use Tools › **Set tee here** and **Set green here** on each hole to pin the real spots. They're saved on the phone and used from then on.

## Side games for money

Set dollar stakes when you start a round, or later from Stakes on the scorecard's Side games tab: an amount per skin and per Nassau leg. Each other player in the group pays the skin winner the per-skin amount for every skin won. So if Chris wins 2 skins at $10, Jake and Dev each owe Chris $20. A Nassau leg (front 9, back 9, overall) pays its leader once the leg is finished; a tied leg pays nobody.

Settle up shows who is up or down and the fewest payments that square everyone, such as "Jake pays Chris $20". Each payment has Pay on Venmo or Pay on Cash App buttons that open the app with the amount and a note filled in, plus a check to mark it paid. Golfers add their Venmo username and $Cashtag in Edit profile.

Gimme never holds or moves the money. Taking deposits and paying out winnings would make Gimme a real-money gaming app and a money transmitter, which needs state licenses and Apple's approval as a gambling app. Settling directly between friends avoids all of that.

## Community feed and going live

Community works like TikTok meets LinkedIn. You swipe up through full-screen posts: video clips filmed on the course, prizes won, finished rounds, and friends going live. Each post carries the golfer's card the way LinkedIn does, with their name, handicap, home course and a Connect button, and prizes and rounds get a Congratulate button. The tabs are For You (the hottest posts first, with live rounds pinned on top), Following (your friends), and Network (your profile card, who's live now, the handicap leaderboard and your friends).

The app posts on its own (golfers can turn this off in Edit profile):
- **Prize won:** when a golfer wins a drop, a post with the prize photo and the hole.
- **Trending hole:** when a golfer reaches a hole where someone else's clip is trending (most likes, comments and views in the last 60 days), a post saying they're taking it on. The GPS screen also shows the clip so they can watch it.
- **Going live:** when a golfer goes live.

Clips are filmed from the Clip button on the GPS screen, or the + on Community, and tagged with the hole. They upload to the public `clips` storage bucket in Supabase.

**Going live.** The Go live button on the GPS screen lets friends watch the round. They see where the golfer is on the satellite hole and the distance left, every score as it goes in, and they can send cheers. "Stream my camera" adds live video through LiveKit. To turn it on:
1. Create a project at [LiveKit Cloud](https://cloud.livekit.io) and copy its URL, API key and API secret.
2. `supabase secrets set LIVEKIT_URL=wss://<project>.livekit.cloud LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=...`
3. `supabase functions deploy livekit-token` (the function is in `supabase/functions/livekit-token`).

The function checks that only the golfer who went live can stream, and only friends of a live round (or players in it) can watch. In the demo, Jake is live at Turtle Point so you can try watching without a server; the camera needs the real setup.

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
