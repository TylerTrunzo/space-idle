# Building and running Space Idle

The game is a Flutter app in `app/`, built on the pure-Dart economy engine in
`packages/game_core`. They sit in one pub workspace with `packages/game_sim`,
the headless simulator. The commands below use Flutter 3.50.1 (Dart 3.14),
installed at `/opt/flutter` in the dev container.

```
export PATH=/opt/flutter/bin:$PATH
flutter pub get            # once, from the repository root
```

## Play it in a browser (development)

```
cd app
flutter run -d web-server --web-port 8080
```

Then open <http://localhost:8080>. `web-server` serves a debug build. Press
`r` in the terminal to hot-reload and `q` to stop. `flutter run -d chrome`
works too, where Chrome is installed.

## Build the web release

```
cd app
flutter build web --release --no-web-resources-cdn
```

The site lands in `app/build/web`. `--no-web-resources-cdn` bundles CanvasKit,
so the page loads nothing from outside its own server. Serve it with any
static server, for example:

```
python3 -m http.server 8080 --directory app/build/web
```

The game saves in the browser's local storage. Settings → Copy save copies
the save as text, and Load save restores it.

## The web smoke test

`tool/web_smoke.mjs` drives the release build in headless Chromium with
Playwright. It needs Playwright and its Chromium, which are preinstalled
globally in the dev container. Serve the build as above, then run from the
repository root:

```
NODE_PATH="$(npm root -g)" node tool/web_smoke.mjs
```

Options:

| Option | Default | What it sets |
|---|---|---|
| `--url` | `http://127.0.0.1:8080/` | The page to test |
| `--save` | `packages/game_core/test/fixtures/balanced_s1_d14.json` | The late save it loads (a day-14 bot game) |
| `--out` | `docs/screenshots` | Where the screenshots go |
| `--seconds` | `10` | How long each frame timing runs |

At 412×915 (a phone) it does this:

1. Waits for the app and turns Flutter's semantics on.
2. Checks that the star map shows Kora within 20 s.
3. Screenshots the map, Kora's panel and the Projects tab.
4. Loads the late save through Settings → Load save, then screenshots it.

At 1280×800 it screenshots the map and the side panel.

It also times frames over 10 s, with `requestAnimationFrame` and Chrome's own
counters, in three cases: a new game, the late save on the map, and the late
save on the Trade tab. It prints the figures as JSON.

It exits with 1 when a step fails, or when the page logs a console error or
throws. Screenshots are taken at device scale factor 2.

Headless Chromium has no GPU, so it draws with a software renderer. Frame
rates on the animated star map there are far below a real phone's. Take its
timings as a relative check (a new game against a late save, one build
against the next), not as a device figure.

## Build the Android APK

Building the APK needs the Android SDK, which the dev container can't
download. The **Android APK** GitHub Actions workflow
(`.github/workflows/android.yml`) builds it on every push and can also be run
by hand (Actions → Android APK → Run workflow).

To get the APK:

1. Open the repository on GitHub, then **Actions → Android APK**.
2. Open the latest green run for your branch.
3. Under **Artifacts**, download `space-idle-apk`. It is a zip holding
   `app-release.apk`.

Where the Android SDK is installed, `cd app && flutter build apk --release`
builds the same file into `app/build/app/outputs/flutter-apk/`.

The APK is a release build signed with the debug key. It installs for
testing, but it can't be uploaded to Google Play. Its application id is the
placeholder `com.spaceidle.game`.

### Installing it on an Android phone (sideloading)

1. Copy `app-release.apk` to the phone, or download the artifact on the phone
   and unzip it there.
2. Open the APK from the Files app or the browser's downloads.
3. Android asks to allow installs from that app (Settings → Apps → Special
   app access → Install unknown apps). Allow it for the app you opened the
   APK with, then go back and tap **Install**.
4. Play Protect may warn that the app is from an unknown developer. Choose
   **Install anyway**. The warning is expected for a debug-signed test build.

To update, install the newer APK over the old one; the save is kept. A build
signed with a different key (a future Play release, for example) won't
install over this one: uninstall first, which deletes the save. Settings →
Copy save keeps a copy of the save before you do.

## Checks

From the repository root, as CI runs them (`.github/workflows/ci.yml`):

```
dart analyze --fatal-infos
(cd packages/game_core && dart test)
(cd packages/game_sim && dart test)
(cd app && flutter analyze --fatal-infos && flutter test)
(cd app && flutter build web --release --no-web-resources-cdn)
```

The game content lives in `content/*.json`. After changing it, run
`dart run tool/embed_content.dart` to regenerate
`app/lib/generated/content_bundle.g.dart`; a test fails when the two differ.
