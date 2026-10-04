# Movi for iOS

Native Netflix-style iOS app for the Movi personal streaming site
(https://movi.byethost6.com). SwiftUI + AVKit, no web views.

## Screens

- **Login** — email + password (same account as the site)
- **Profiles** — "Who's watching?" picker
- **Home** — hero banner, Continue Watching (with progress bars),
  recently added movies/shows, genre rows
- **Detail** — movie/show pages with overview, My List toggle, episode lists
- **Player** — native fullscreen AVPlayer, resume-from-last-position,
  progress reporting, auto up-next episode
- **Search** — titles across movies + shows
- **My List** — favorites

## Backend

The app talks to the site's JSON API (`api.php`) using the same PHP
session cookie as the web login, so auth, watch state, favorites and
profiles stay in sync with the site. Video streams via the worker's
signed Telegram-proxy URLs (plain HTTP — see the ATS exception in
`Info.plist`).

Required site endpoints (shipped in Movi v0.100+): `app_login`,
`app_logout`, `app_profiles`, `app_profile_select`, `app_home`,
plus `playback` on the `movie` detail endpoint.

## Build

GitHub Actions builds an **unsigned** IPA on every push to `main`
(`.github/workflows/build-ipa.yml`):

1. `xcodebuild` with `CODE_SIGNING_ALLOWED=NO`
2. `Movi.app` is zipped as `Payload/Movi.app` → `Movi-unsigned.ipa`
3. The IPA is uploaded as the `Movi-unsigned-ipa` artifact

## Install with Sideloadly

1. Download `Movi-unsigned.ipa` from the workflow run's artifacts.
2. Open Sideloadly on your computer, connect your iPhone.
3. Drag the IPA into Sideloadly, enter your Apple ID when asked.
4. Sideloadly signs it with your Apple ID and installs it.

Note: free Apple IDs expire every 7 days — Sideloadly can refresh
automatically over WiFi. A paid Apple Developer account ($99/yr)
extends this to a year.

## Project layout

- `Movi/MoviApp.swift` — entry point + root router
- `Movi/Models.swift` — API models
- `Movi/APIClient.swift` — JSON API client (session cookies)
- `Movi/AppState.swift` — login/profile/session state
- `Movi/Views/` — Login, Profiles, Home, Detail, Player, Search, Library
- `Movi/Info.plist` — bundle config + ATS exception for the video worker
- `Movi/Assets.xcassets` — app icon + launch background
