# Getting Gimme onto TestFlight

Do these in order. Steps 1 to 3 can take Apple a day or two, so start them first.

## 1. Apple Developer Program

1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/enroll/) ($99 a year). Enrolling as an individual is fastest; a company needs a D-U-N-S number and takes longer.
2. When it's approved, open [Membership details](https://developer.apple.com/account#MembershipDetailsCard) and copy your **Team ID** (10 letters and numbers).

## 2. The app record in App Store Connect

1. In [Certificates, Identifiers & Profiles › Identifiers](https://developer.apple.com/account/resources/identifiers/list), add an **App ID** with bundle ID `com.gimmegolf.app`. Leave capabilities as they are.
2. In [App Store Connect › Apps](https://appstoreconnect.apple.com/apps), click **+ › New App**: platform iOS, name **Gimme** (if it's taken, use **Gimme Golf**; the name under the icon stays "Gimme"), language English (U.S.), bundle ID `com.gimmegolf.app`, SKU `gimme`.

## 3. An API key so builds upload themselves

1. In App Store Connect go to **Users and Access › Integrations › App Store Connect API › Team Keys** and generate a key with the **Admin** role. Admin is needed because the build creates its own signing certificate.
2. Copy the **Issuer ID** and **Key ID**, and download the `.p8` file. Apple only lets you download it once.

## 4. GitHub

Create the repository and add these under **Settings › Secrets and variables › Actions › New repository secret**:

| Secret | What to paste |
| --- | --- |
| `APPLE_TEAM_ID` | Team ID from step 1 |
| `ASC_KEY_ID` | Key ID from step 3 |
| `ASC_ISSUER_ID` | Issuer ID from step 3 |
| `ASC_KEY_P8` | The whole text of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

Every push to `main` then tests the app and uploads a new build to TestFlight (**Actions › TestFlight**). You can also run it by hand with **Run workflow**.

## 5. Privacy policy and support pages

Apple needs public links to them. The pages are in `website/`.

- In the repository go to **Settings › Pages**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`. Your links are then `https://<you>.github.io/<repo>/website/privacy.html` and `.../website/support.html`.
- Replace the placeholder `support@gimmegolf.app` in the three pages with an inbox you read.
- Put the terms and privacy links in `project.yml` (`GimmeTermsURL`, `GimmePrivacyURL`) so the app opens the right pages.

## 6. Supabase (accounts and data)

1. Create a project at [supabase.com](https://supabase.com/dashboard). Under **Project Settings › API**, copy the **Project URL** and the **anon public** key into `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `project.yml` (they are public by design).
2. In **SQL Editor**, run `supabase/schema.sql`, then `supabase/seed-palmetto-pine.sql` (the Palmetto & Pine drops on the Kiawah courses).
3. **Authentication › Emails**: in both **Magic Link** and **Confirm signup**, set the subject to `Your Gimme code` and the body to `<h2>Welcome to Gimme</h2><p>Your sign-in code is <strong>{{ .Token }}</strong></p>`. Without this, testers get a link instead of the 6-digit code the app asks for.
4. **Authentication › Emails › SMTP Settings**: turn on custom SMTP. Supabase's built-in email only reaches members of your Supabase team, so testers would never get a code. A Gmail account works for a beta: turn on 2-Step Verification, create an app password (Google Account › Security › App passwords), then use host `smtp.gmail.com`, port `465`, the Gmail address as username and sender, and the app password.
5. **Authentication › Users › Add user**: create a reviewer account with an email and a password, and tick **Auto Confirm User**. Apple's reviewer signs in by typing that email, tapping **Email me a code**, then **Sign in with a password instead**.

## 7. LiveKit (live video)

1. Create a project at [cloud.livekit.io](https://cloud.livekit.io). Under **Settings › Keys**, create a key and note the URL (`wss://...livekit.cloud`), API key and secret.
2. With the [Supabase CLI](https://supabase.com/docs/guides/cli) on your computer, in this repository:

```sh
supabase login
supabase link --project-ref <your project ref>
supabase secrets set LIVEKIT_URL=wss://<your-project>.livekit.cloud LIVEKIT_API_KEY=<key> LIVEKIT_API_SECRET=<secret>
supabase functions deploy livekit-token
```

Everything else in live rounds works without this; only the camera stream needs it.

## 8. Testers

- **Internal testing** (fastest): add friends in App Store Connect **Users and Access** (any role, for example Marketing), then add them to an internal group in **TestFlight**. Up to 100 people, no Apple review, and they can install as soon as a build finishes processing.
- **External testing** (anyone with a link, up to 10,000): create an external group in **TestFlight**, add a build, and turn on the **public link**. The first build goes through Beta App Review, usually within a day. Apple asks for:
  - a beta description and what to test;
  - a feedback email;
  - the privacy policy URL from step 5;
  - sign-in details: the reviewer email and password from step 6, with the note *"Tick the terms box, type the email and tap Email me a code. On the next screen tap Sign in with a password instead."*

Testers install **TestFlight** from the App Store, open your invite or link, and tap **Install**.
