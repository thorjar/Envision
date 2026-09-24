# Envision for Apple TV

The tvOS app uses SwiftUI and AVKit with direct references to Envision's existing authentication, models, artwork, API, and playback engine. The original Xcode project remains separate.

## Open and run

Open `/Users/jaret/github_repos/Envision/EnvisionTV.xcodeproj` and select the **EnvisionTV** scheme. Minimum OS: **tvOS 18**. Choose your signing team to run on an Apple TV. For simulator execution, install a tvOS runtime in Xcode Settings → Components.

Sign in using your existing Jellymax server URL and account. Use the server's LAN address or hostname, not `localhost` or `127.0.0.1` (which refer to the Apple TV itself). First-run server setup and administration are performed in the existing apps.

The app permits HTTP to support user-configured LAN servers. HTTPS is strongly recommended, especially outside your home network: HTTP sends credentials and media without transport encryption. No server credentials are included in the app.

## Features

- Remote-focusable artwork cards and top-level tabs (tab bar appears by pressing MENU at a screen's top level)
- MENU/escape pops pushed pages; at a tab's root it returns to the Home tab instead of leaving the app (at Home's own root it exits, per tvOS convention)
- While the Audio & Subtitles picker is open, MENU closes only the picker and playback continues; selecting a track resumes the stream at your position
- Switching tabs always reopens that tab at its root, never at a previously viewed series/movie
- Continue Watching in landscape backdrops; recently added and recommendations
- Favorites and Search split into Movies (portrait posters) and Series (landscape backdrops) sections
- Libraries, inline series → season → episode shelves, previous/next episode navigation, paginated catalogs, search, and playlist browsing
- Item details, favorite and watched-state controls
- Full-screen native AVKit controls, seeking, stream-provided audio/subtitle selection
- Audio & Subtitles lives in the player's transport bar, so it appears with the controls and is reached with the same arrows; embedded soundtracks switch server-side with resume, embedded subtitles render as windowed VTT captions on screen, and OpenSubtitles search (in the same picker) downloads and renders captions on the spot
- Resume/from-beginning playback and server progress/stopped reporting
- Keychain-backed sign-in and sign-out/server switching

## Build without a simulator runtime

```sh
xcodebuild -project /Users/jaret/github_repos/Envision/EnvisionTV.xcodeproj \
  -target EnvisionTV -sdk appletvsimulator \
  SYMROOT=/tmp/envision-tv-products CODE_SIGNING_ALLOWED=NO build
```

The project is generated with XcodeGen (build-time tooling only, not an app dependency). After adding source files, regenerate it:

```sh
xcodegen generate --spec /Users/jaret/github_repos/Envision/project-tv.yml
```

## Scope and release checklist

This is an initial TV client, not an App Store-ready release. It needs Apple TV hardware testing with a real server: sign-in/restoration, remote focus/back behavior, long catalogs, direct play and transcoding, resume accuracy, track selection, and final progress after exit. Unsupported formats require compatible server transcoding.

There is no TV runtime installed in the development environment, so a successful SDK build does not establish runtime correctness. App Store layered icons/Top Shelf artwork still need to be supplied. Top Shelf integration, automatic next-episode/playlist queue playback, PiP/background playback, subtitle file import, and server administration are not implemented on TV. Audio and subtitle pickers cover embedded (server-delivered) tracks, the stream's own renditions, and OpenSubtitles search/download through the server's provider; importing local SRT/VTT files is available only in the iOS/Mac apps.
