# LedgeKit developer preview

LedgeKit is the Swift package for authoring Ledge add-ons. It currently supports
the version-1, one-request executable transport used by Spotify Likes.
Requires Swift 6 and macOS 14 or later.

## Add the library

During development, place your add-on beside a LedgeKit checkout and declare:
    
```swift
dependencies: [.package(path: "../LedgeKit")],
targets: [
    .executableTarget(name: "MyAddOn", dependencies: ["LedgeKit"])
]
```

The SDK is public. Add-ons can pin the released SDK without GitHub credentials:
```swift
.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "0.1.0")
```
Community submission and publication instructions are in
[LedgeAddOns](https://github.com/Ammyy9908/LedgeAddOns).
The SDK currently ships the library product LedgeKit and executable ledgekit.

## Run a session (protocol 2, 0.3.0)

A session add-on stays running while it's enabled. Ledge starts it once, sends `hello`, then requests, one JSON
message per line on stdin, and reads replies from stdout. Set `"protocolVersion": 2` in addon.json.

```swift
import Foundation
import LedgeKit

var handlers = AddOnHandlers()
handlers.activate = { /* start timers and observers */ }
handlers.deactivate = { /* stop everything activate started */ }
handlers.on("greet") { (request: [String: String]) in
    ["text": "Hello, \(request["name"] ?? "there")"]
}
exit(await AddOnSession.run(id: "my-addon", handlers: handlers))
```

- Requests run side by side and answer in any order. Throw `AddOnError("…")` for a message the user can see;
  any other error reaches Ledge as a generic failure.
- `AddOnSession.log(_:)` writes to Ledge's log. Never log credentials or what the user typed. stderr is kept only
  as the last lines of diagnostics.
- The session ends when Ledge closes stdin. Ledge stops anything still running in the add-on's session after
  that, and restarts an add-on that crashes, at most three times.
- Messages are limited to 1 MB. See `SessionProtocol` for the full exchange.

## Put something on screen (surfaces, 0.5.0)

A session add-on describes its surfaces as data; Ledge draws them with its own views. Declare them in addon.json
(`"surfaces": ["settings-page", "widget"]`), then send them whenever they change:

```swift
handlers.activate = {
    AddOnSession.show(SettingsPage([
        SettingsSection("display", title: "Display", rows: [
            .toggle("showLit", "Show how much is lit", isOn: true),
            .picker("units", "Units", options: [.init("km", "Kilometres"), .init("mi", "Miles")], selected: "km"),
            .button("refresh", "Refresh")
        ])
    ]))
    AddOnSession.show(widgets: [
        Widget("moon", title: "Moon", symbol: "moon.fill", content: .vstack(spacing: 6, children: [
            .text("Waxing gibbous", style: .title),
            .progress(0.78, label: "78% lit"),
            .button(id: "next", title: "Next full moon", symbol: "calendar")
        ]))
    ])
}
handlers.onEvent = { event in
    // event.control is the row or button id; event.action says what happened.
}
```

- Settings rows: toggle, picker, slider, text field, button, link, read-only value, note. Widgets: vertical and
  horizontal stacks, text, SF Symbols, a progress bar, buttons and spacers.
- Each send replaces the last. Ledge keeps controls whose ids don't change, so a field being typed in isn't reset.
- Ledge draws only surfaces the manifest declares, and refuses descriptions over its limits (200 rows, 8 widgets,
  100 parts and 6 levels per widget, 1,000 characters per text).

## Ask Ledge for things (host services, 0.6.0)

A session add-on can call Ledge through `LedgeHost`, from any handler, including `activate`:

```swift
struct Choices: Codable { var units: String }
handlers.activate = {
    let saved = try? await LedgeHost.value(Choices.self, forKey: "choices")   // kept across restarts and updates
    let environment = try await LedgeHost.environment()                      // Ledge version, light or dark, accent, notch
    try await LedgeHost.set(Choices(units: "km"), forKey: "choices")
}
handlers.onEvent = { event in
    try? await LedgeHost.open(URL(string: "https://example.com")!)            // https, http and mailto only
    try? await LedgeHost.copy("Copied from my add-on")                       // needs "clipboard-write"
    try? await LedgeHost.notify(title: "Done", message: "It worked")         // needs "hud"
}
```

- Accounts Ledge manages: `LedgeHost.account("spotify")` says whether the user is connected, and
  `LedgeHost.request(provider: "spotify", method: "GET", path: "/v1/me/library/contains", query: ["uris": …])` asks
  Ledge to call the provider with the user's credentials. Ledge allows only the endpoints it lists for the
  capability you were granted (for Spotify, `spotify-library`: the library's contains, save and remove), adds the
  credentials itself, and returns the status and body. Your add-on never receives a token.
- Ledge tells you when its environment changes (light or dark, the accent colour, displays), from 0.9.0:
  `handlers.onEnvironmentChange = { environment in … }` gets the same value `environment()` returns.
- Stored settings are per add-on: keys up to 128 characters, all values together up to 256 KB. They survive
  restarts, updates, and removing and reinstalling the add-on.
- A call Ledge refuses throws `LedgeHostError` with the reason, for example a capability the user didn't grant.
  Handle it: capabilities can be off. Calls Ledge doesn't answer within 10 seconds throw too.

## A button in Ledge's players (player actions, 0.7.0)

Declare `"player-action"` in the manifest's `surfaces`, show the button, and answer its state per song:

```swift
let heart = PlayerAction("like", label: "Like", symbol: "heart", selectedSymbol: "heart.fill",
                         sources: ["com.spotify.client"])
handlers.activate = { AddOnSession.show(playerActions: [heart]) }
handlers.onPlayerAction = { request in
    guard let id = request.track.id else { return nil }        // nil: unknown, drawn dimmed
    if let liked = request.set { return try await setLiked(liked, id) }
    return try await isLiked(id)
}
```

- Ledge draws the button in the notch, menu bar, floating and lock screen players while a song from one of
  `sources` plays, and decides where it goes. Up to 4 actions per add-on.
- `request.set` is nil when Ledge asks the state, and the state the user chose when they press it. Answer the
  state after it. A press while the state is unknown opens your settings page instead.
- A settings row `.account("spotify", "Spotify", provider: "spotify")` shows Ledge's own sign-in for an account it
  manages, so users sign in from your page while the credentials stay in Ledge.

## A player menu and Playing Next (player extensions, 0.8.0)

Declare `"player"` in `surfaces` and say which players you cover:

```swift
AddOnSession.show(player: PlayerExtension(sources: ["com.apple.Music"],
                                          menu: PlayerMenu("playlists", title: "Add to Playlist", symbol: "text.badge.plus"),
                                          queue: true))
handlers.onPlayerMenu = { request in
    if let id = request.choose { try await add(to: id); return [] }   // the user picked an item
    return try await playlists().map { PlayerMenu.Item($0.id, title: $0.name) }
}
handlers.onPlayerQueue = { request in
    if let id = request.playNext { try await playNext(id) }           // the user picked an upcoming song
    return try await upcoming()                                         // [PlayerQueueEntry], up to 50
}
```

- The menu entry appears in the player's ••• menu and lists your items when it opens. Playing Next appears in the
  notch, menu bar and lock screen players; Ledge loads each entry's artwork from its https `artworkURL`, or by its
  Apple `storeID`.
- `show(player: nil)` removes both. Throw `AddOnError` from `onPlayerQueue` with a reason, and Ledge shows it in
  place of the list.

## Live activities beside the notch (0.10.0)

Declare `"activity"` in `surfaces`, then show the activities you have up; each send replaces the last:

```swift
AddOnSession.show(activities: [
    LiveActivity("countdown", symbol: "timer", text: "4:59", progress: .fraction(0.2), importance: .high)
])
AddOnSession.show(activities: [])                       // take them down
handlers.onActivityPlacement = { change in               // center, side, outranked, suppressed or idle
    if change.placement == .suppressed { stopSending() }
}
```

- Ledge's own activities (volume, charging, media…) always come first; yours takes the centre only when none of
  Ledge's is up, and otherwise a side pill or nothing. Up to two activities, 60 characters of text each.
- `lasts:` takes an activity down after that many seconds (1–600); without it, it stays until you take it down.
  Take it down as soon as it has nothing to say.
- Users can turn an add-on's activities off on its page; you're told `.suppressed`. `Examples/Timer` shows it all.

## The lock screen and the menu bar (0.11.0)

```swift
AddOnSession.show(lockScreenRow: LockScreenRow(symbol: "timer", label: "Timer", value: "4:59"))  // nil takes it down
AddOnSession.show(menuBarTiles: [MenuBarTile("toggle", symbol: "timer", title: "Start a timer", detail: "1 minute")])
handlers.onEvent = { event in
    if event.surface == Surface.menuBarTile, event.control == "toggle" { toggle() }
}
```

- Declare `"lock-screen-row"` and `"menu-bar-tile"` in `surfaces`. One lock screen pill per add-on (label up to 30
  characters, value up to 20), shown under the clock only while the Mac is locked; up to two menu bar tiles, as rows
  under Ledge's own in its menu bar panel.

## A page in the notch (0.12.0)

```swift
let list = PageScreen("list", title: "Notes",
    actions: [PageAction("new", symbol: "square.and.pencil", label: "New note")],
    content: .list(id: "notes", rows: [ListRow("n1", title: "Launch day", subtitle: "Beta 2 goes out", detail: "12:41 PM")]))
AddOnSession.show(notchPage: NotchPage(title: "Notes", symbol: "note.text", size: .medium, screen: list))  // nil takes it down

handlers.onEvent = { event in
    guard event.surface == Surface.notchPage else { return }
    if event.control == "notes", let id = event.item { openNote(id) }          // a row: the list's id, then the row's
    if event.control == PageScreen.backControl { showList() }
    if event.control == "body", case .ended(let markdown) = event.action { save(markdown) }
}
```

- Declare `"notch-page"` in `surfaces`. One page per add-on, with its icon in the pill under the open notch, after
  Ledge's Shelf, Clipboard and Widgets.
- The page shows one screen at a time. Send the next screen to move to it: Ledge slides forward when its `depth` is
  greater, back when it's less. A header can have a back button, a title or caption, and up to three buttons.
- Screens are made of a widget's parts plus `.list`, `.empty` and `.editor`. The editor's text is Markdown (bold,
  italic, headings, lists and checklists); it sends `.edited` as someone types and `.ended` when they leave it, and
  Ledge keeps their text if the screen is sent again meanwhile.
- Limits: 200 parts per screen, 100 rows per list, 3 header buttons, one editor of up to 50,000 characters.

## Good add-ons (0.13.0)

```swift
handlers.onVisibilityChange = { visibility in            // which of your surfaces are on screen
    if visibility.isVisible(Surface.notchPage) { await notes.reload() }
}
let folder = try await LedgeHost.dataFolder()            // your own files, kept through updates
try await LedgeHost.showPage()                           // just after a press, or for an .attention activity
try await LedgeHost.openSettings()                       // just after a press, for a "Set up" button
try await LedgeHost.holdOpen(true)                       // while something the user watches runs
```

- `showPage` and `holdOpen` need the `notch-control` capability. Ledge refuses `showPage` from a timer.
- `LiveActivity` gains `kind` (`.nowPlaying`, `.download`, `.recording`), which steps aside for Ledge's own of the
  same kind (placement `duplicatesBuiltIn`), and `accessibilityValue`. `.attention` sits above `.high`. A `.high`
  or `.attention` activity that says the same thing for half an hour is placed `stale` until it changes.
- A settings button can ask first: `.button(id, title, destructive: true, confirm: .init(...))`. A page can carry
  `keywords` for Ledge's Settings search.

## Implement a worker (protocol 1)

```swift
import LedgeKit

@main
struct Example {
    static func main() async {
        await AddOnWorker.run { request in
            // Validate your operation and inputs before performing an action.
            return AddOnResponse(value: request.liked ?? false)
        }
    }
}
```

This example demonstrates the transport. Ledge currently installs only the Spotify
Likes adapter. A different package cannot yet register player controls or settings.

The host writes one JSON request and closes stdin. The SDK reads at most 64 KiB
plus one byte to detect overflow, rejects malformed or incompatible requests,
invokes the handler and writes one JSON response. stdout is reserved for this
response. Use stderr for diagnostics and never log tokens or full requests.

The SDK returns a generic error for thrown handler errors to avoid disclosing
credentials. Provider-specific input validation remains the handler's responsibility.
The host owns deadlines and process termination. A blocked input or handler has
no independent worker timeout. Host output limits and lifecycle messages are pending.

## Package metadata

Use AddOnManifest's public initializer, call validate(), then JSONEncoder to
produce addon.json. Existing version-1 JSON without an icon remains compatible.

Required keys: id, version, protocolVersion, name, summary, description, author,
capabilities, executable. Optional icon points to Assets/<filename>.png.
The version format is three nonnegative decimal integers. Protocol version is 1.
The only currently supported capability is spotify-library. Empty capabilities
are valid metadata but do not add host functionality.

Validation throws ManifestValidationError with an invalid field, unsupported
protocol, or unsupported capability. New strict checks reject previously accepted
malformed versions, duplicate capabilities and blank author/name values.

## Validate and build

From the LedgeKit repository root:

```sh
swift run ledgekit validate /path/to/your/addon.json
swift build
swift test
```

CLI exit codes: 0 valid, 1 invalid/unreadable, 2 incorrect usage. The CLI checks
metadata only. The host additionally validates executable and image files.
It does not certify trust, signatures, compatibility with arbitrary capabilities,
or successful installation.

## Support and roadmap

Implemented: manifest authoring/validation, metadata validation CLI, bounded
version-1 input, worker dispatch, example Spotify integration.

Pending: generic package registry and contributions, persistent lifecycle,
capability-scoped host services, credential broker, sandbox enforcement,
CLI scaffolding/build/install, Playground and community publishing.

Version 1 supplies an access token to trusted native code. A subprocess is not a
sandbox. Keep this developer preview restricted to trusted code until sandboxing,
capability enforcement, lifecycle isolation and reviewed distribution are verified.

## Notification banners (0.2.0)

Version 0.2.0 adds the `notification-banners` capability and
`NotificationBannerRequest` / `NotificationBannerResponse` contracts. These are
separate from the unchanged Spotify transport. A consenting host supplies a title,
body and preview preference; the response limits text to 8,450 characters and
replaces the body with “New notification” when previews are off. Hosts enforce
request/response size limits, execution timeouts, local trust and lifecycle.
These APIs require SDK 0.2.0 or later. See the host's Notifications example
for the bounded one-request executable adapter.
