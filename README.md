# Bluetooth Hanabi

A native iOS app for playing the cooperative card game [Hanabi](https://en.wikipedia.org/wiki/Hanabi_(card_game))
with friends nearby, over Bluetooth/Wi-Fi (via MultipeerConnectivity) — no server, no internet
required. Built for the standard 5-color game, 2 players first, extensible to 3–5.

## Layout

- **`HanabiKit/`** — a pure-Swift Swift package with the full rules engine (`HostGame` /
  `HanabiEngine`) and the network message protocol. No UIKit/SwiftUI/MultipeerConnectivity
  dependency, so it's independently unit-testable (`HanabiKitTests`).
- **`BluetoothHanabi/`** — the iOS app (SwiftUI + MultipeerConnectivity), which depends on
  `HanabiKit` as a local Swift package.

```
BluetoothHanabi/BluetoothHanabi/
  BluetoothHanabiApp.swift        entry point
  Networking/MultipeerManager.swift   thin MultipeerConnectivity wrapper
  ViewModels/GameViewModel.swift      owns app state, routes network messages, applies actions
  Views/                              SwiftUI screens (menu, lobby, game table, hint sheet, game over)
```

## How multiplayer works

One player **hosts** (advertises over the network); everyone else **joins** by browsing for
and connecting to that host. It's a star topology — clients only ever talk to the host, never
to each other — which is what makes this scale from 2 players up to 5 without any extra work.

The host runs the only authoritative copy of the game state (`HostGame`, including the private
draw pile) and broadcasts the full `GameState` to every client after each move. Clients send
their intended move as a `GameAction`; the host validates it (right turn, legal card index,
hint actually matches a card, etc.) before applying it and re-broadcasting.

**Trust model:** in real Hanabi you can see everyone's hand except your own. The broadcast
`GameState` actually contains everyone's true card values — the app just doesn't render your
own hand's card faces in the UI, only whatever hints have revealed about them. This is a
deliberate simplification for a phones-on-the-couch party game between friends: it's not
tamper-proof against someone reading their own device's network traffic, the same way you
wouldn't expect protection against someone looking at another player's screen in real life.

## Rules implemented

Standard base-game Hanabi: 5 colors × 10 cards each (three 1s, two 2s/3s/4s, one 5), 8 hint
tokens, 3 lives, hand size 5 for 2–3 players / 4 for 4–5 players. Completing a color's stack to
5 refunds a hint token. Discarding is disabled at 8 hint tokens (nothing to gain). Three
mistakes ends the game immediately with a score of 0 (official rule). When the deck runs out,
every player gets exactly one more turn (including the player who drew the last card), then
final score is the sum of the five stacks.

## Building it

This was developed in an environment with only Xcode Command Line Tools (no full Xcode, no iOS
SDK) — the `HanabiKit` engine was verified independently (`swift test`-equivalent), and the app
layer was typechecked against the macOS SDK where APIs overlap, but **the app itself has not
been built or run**, since that needs a full Xcode install. To build and run it:

1. Open `BluetoothHanabi/BluetoothHanabi.xcodeproj` in Xcode (15+ recommended; deployment
   target is iOS 16).
2. Select the `BluetoothHanabi` target → Signing & Capabilities, and set your own Team (and
   probably change `PRODUCT_BUNDLE_IDENTIFIER`, currently `com.example.BluetoothHanabi`, to
   something under your own prefix).
3. Build & run on two physical iOS devices for a real Bluetooth test. Simulators cannot do
   real Bluetooth; two simulators (or a simulator + a device) on the same Wi-Fi network can
   often still discover each other via MultipeerConnectivity's Wi-Fi/Bonjour path, but it's
   not guaranteed — physical devices are the reliable way to test this.
4. On one device tap **Host Game**; on the other tap **Join Game** and pick the host from the
   list. Once 2+ players are in the lobby, the host can start.

To run just the engine's unit tests (fast, no simulator needed):
```bash
cd HanabiKit && swift test
```

## CI: building a signed .ipa via GitHub Actions

`.github/workflows/build-ipa.yml` builds and archives a signed `.ipa` on a `macos` runner and
uploads it as a workflow artifact. It runs on every push to `main` and can also be triggered
manually from the Actions tab. It needs your Apple Developer signing materials as **repo
secrets** (Settings → Secrets and variables → Actions → New repository secret) — nothing here
is usable without them:

| Secret | What it is |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Your distribution (or development) `.p12` certificate, base64-encoded: `base64 -i Certificate.p12 \| pbcopy` |
| `P12_PASSWORD` | The password you set when exporting that `.p12` from Keychain Access |
| `BUILD_PROVISION_PROFILE_BASE64` | The matching `.mobileprovision`, base64-encoded: `base64 -i Profile.mobileprovision \| pbcopy` |
| `KEYCHAIN_PASSWORD` | Any password string — used only for a throwaway CI keychain |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |

The provisioning profile's App ID must match the bundle identifier the build uses. By default
that's `com.example.BluetoothHanabi` (a placeholder — change it, either by editing
`PRODUCT_BUNDLE_IDENTIFIER` in Xcode, or by setting an `IOS_BUNDLE_IDENTIFIER` repo **variable**
to match your real App ID without touching the project). An `IOS_EXPORT_METHOD` repo variable
(`development` | `ad-hoc` | `app-store` | `enterprise`) controls the export method; it defaults
to `development`, which means the profile must list every device's UDID you want to install on
(this repo's provisioning profile choice, not something the workflow can work around).

Once the secrets are set and a run finishes successfully, download the `.ipa` from the
**Summary** page of that workflow run, under **Artifacts**.

## Extending beyond 2 players

The architecture already supports 3–5 players — `HostGame`/`HanabiEngine` take a player count
in that range, hand size adjusts automatically, and MultipeerConnectivity's star topology
doesn't care how many clients are connected to the host. The lobby caps at 5 players
(`LobbyState.maxPlayers`). Testing with more than 2 devices just needs more devices; no code
changes required.

## Known limitations / next steps

- No reconnect handling if a player's connection drops mid-game.
- No AI/solo player (by design, per the original ask).
- Portrait orientation only; the table layout isn't tuned for landscape or iPad yet.
- No persistence — closing the app mid-game loses that game.
