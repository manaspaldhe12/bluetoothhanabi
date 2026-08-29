# Bluetooth Hanabi

**⬇️ [Download the latest build (BluetoothHanabi.ipa)](https://github.com/manaspaldhe12/bluetoothhanabi/releases/download/latest/BluetoothHanabi.ipa)** — unsigned, rebuilt automatically on every push to `main`. See [Install on your iPhone](#install-on-your-iphone) below for how to sideload it.

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

See "Install on your iPhone" below for two ways to get it onto a device — either sideload the
`.ipa` GitHub Actions builds automatically (no Xcode needed), or build & run straight from
Xcode. Either way you need it on **two physical devices** for a real Bluetooth test (deployment
target is iOS 16; Xcode 15+ if building locally). Simulators cannot do real Bluetooth; two
simulators (or a simulator + a device) on the same Wi-Fi network can often still discover each
other via MultipeerConnectivity's Wi-Fi/Bonjour path, but it's not guaranteed — physical devices
are the reliable way to test this.

On one device tap **Host Game**; on the other tap **Join Game** and pick the host from the list.
Once 2+ players are in the lobby, the host can start.

To run just the engine's unit tests (fast, no simulator needed):
```bash
cd HanabiKit && swift test
```

## Install on your iPhone

### Option A: Without Xcode — sideload the CI-built .ipa (free)

Every push to `main` runs [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml): a GitHub Actions macOS runner with a real Xcode install builds the app, runs the `HanabiKitTests` suite, and publishes an **unsigned** `.ipa` to a rolling `latest` release:

```text
https://github.com/manaspaldhe12/bluetoothhanabi/releases/download/latest/BluetoothHanabi.ipa
```

("Unsigned" here just means CI doesn't hold any Apple credentials — no certificate, provisioning profile, or Apple ID ever touches GitHub Actions. The sideloading tools below strip whatever signature is present and re-sign with your own identity regardless, so a CI-side signature would be pointless complexity.)

You still need **some** computer (Mac or Windows, old or new — it does not need to run Xcode) to do the one-time pairing these tools require; after that, installs/updates can happen straight from your iPhone.

**Using Sideloadly** (simpler, manual refresh every 7 days):

1. Install [Sideloadly](https://sideloadly.io/) on any Mac or Windows computer.
2. Download `BluetoothHanabi.ipa` from the link above.
3. Connect your iPhone by USB, unlock it, and trust the computer if prompted.
4. Open Sideloadly, drag `BluetoothHanabi.ipa` into it, select your device, enter your (free) Apple ID and password when prompted.
5. Click **Start**. Sideloadly signs the app with a certificate generated from your Apple ID and installs it.
6. On your iPhone: **Settings → General → VPN & Device Management**, tap your Apple ID under "Developer App", tap **Trust**.
7. A **free** Apple ID's signature expires after **7 days** — after that the app won't open until you repeat steps 2–6 with a fresh `.ipa` from the same URL (it's always the latest build).

**Using AltStore** (a bit more setup, then refreshes itself over Wi-Fi):

1. Install [AltServer](https://altstore.io/) on a companion Mac or Windows computer and AltStore on your iPhone through it (AltStore's site walks through both — this is a one-time pairing step).
2. Sign in with your free Apple ID when AltServer prompts for it.
3. In AltStore on your iPhone, use **My Apps → +** and pick a downloaded `BluetoothHanabi.ipa`, or add a custom source pointing at the releases feed if you want in-app updates.
4. Same 7-day free-tier limit applies, but AltServer/AltStore will try to auto-refresh the app in the background over Wi-Fi as long as AltServer is reachable (i.e. your companion computer is on and on the same network periodically) — less manual upkeep than Sideloadly once it's set up.

Either way, sideloaded apps are capped at **3 apps signed under a free Apple ID at once**, and every player needs their own sideload of the app on their own phone — remove old test builds if you hit that limit.

### Option B: Direct USB install via Xcode

1. Open `BluetoothHanabi/BluetoothHanabi.xcodeproj` in Xcode, select the `BluetoothHanabi`
   target → Signing & Capabilities, and set your own Team (and probably change
   `PRODUCT_BUNDLE_IDENTIFIER`, currently `com.example.BluetoothHanabi`, to something under
   your own prefix).
2. Connect your iPhone by USB, unlock it, and select it from Xcode's device menu (not a
   Simulator).
3. Press **Run** (⌘R).
4. On first launch, iOS may show **Untrusted Developer** — go to **Settings → General → VPN &
   Device Management**, tap your developer profile, and choose **Trust**.

Simulators cannot do real Bluetooth — physical devices are the reliable way to test multiplayer.

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
