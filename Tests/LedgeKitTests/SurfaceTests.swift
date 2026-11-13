import Foundation
import Testing
import LedgeKit

private let page = SettingsPage([
    SettingsSection("general", title: "General", footer: "Saved on this Mac.", rows: [
        .toggle("enabled", "Show the moon", isOn: true),
        .picker("units", "Units", options: [.init("km", "Kilometres"), .init("mi", "Miles")], selected: "km"),
        .slider("size", "Size", range: 10...40, step: 1, value: 24, unit: "pt"),
        .textField("city", "City", text: "Pune", placeholder: "Find a city"),
        .button("refresh", "Refresh now"),
        .link("site", "Website", url: "https://example.com"),
        .value("phase", "Tonight", "Waxing gibbous"),
        .note("about", "Phases come from a local calculation.")
    ])
])

private let widget = Widget("moon", title: "Moon", symbol: "moon.fill", content:
    .vstack(spacing: 6, children: [
        .hstack(spacing: 8, children: [.symbol("moon.fill", size: 22), .text("Waxing gibbous", style: .title)]),
        .progress(0.78, label: "78% lit"),
        .button(id: "next", title: "Next full moon", symbol: "calendar"),
        .spacer
    ]))

@Test func surfacesRoundTripAsJSON() throws {
    try page.validate()
    try widget.validate()
    #expect(try JSONDecoder().decode(SettingsPage.self, from: JSONEncoder().encode(page)) == page)
    #expect(try JSONDecoder().decode(Widget.self, from: JSONEncoder().encode(widget)) == widget)
    let event = SurfaceEvent(surface: Surface.widget, widget: "moon", control: "next", action: .pressed)
    #expect(try JSONDecoder().decode(SurfaceEvent.self, from: JSONEncoder().encode(event)) == event)
}

@Test func invalidPagesAreRefused() {
    let duplicate = SettingsPage([SettingsSection("a", rows: [.button("x", "One"), .button("x", "Two")])])
    #expect(throws: SurfaceValidationError.duplicateID("x")) { try duplicate.validate() }
    let picker = SettingsPage([SettingsSection("a", rows: [.picker("p", "P", options: [.init("a", "A")], selected: "b")])])
    #expect(throws: SurfaceValidationError.invalid("picker p")) { try picker.validate() }
    let slider = SettingsPage([SettingsSection("a", rows: [.slider("s", "S", range: 0...1, value: 3)])])
    #expect(throws: SurfaceValidationError.invalid("slider s")) { try slider.validate() }
    let link = SettingsPage([SettingsSection("a", rows: [.link("l", "L", url: "file:///etc/passwd")])])
    #expect(throws: SurfaceValidationError.invalid("link l")) { try link.validate() }
    let long = SettingsPage([SettingsSection("a", rows: [.note("n", String(repeating: "x", count: 1001))])])
    #expect(throws: (any Error).self) { try long.validate() }
}

@Test func invalidWidgetsAreRefused() {
    var deep: WidgetNode = .spacer
    for _ in 0..<7 { deep = .vstack(spacing: nil, children: [deep]) }
    #expect(throws: (any Error).self) { try Widget("w", title: "W", symbol: "x", content: deep).validate() }
    let wide = Widget("w", title: "W", symbol: "x", content: .hstack(spacing: nil, children: Array(repeating: .spacer, count: 120)))
    #expect(throws: (any Error).self) { try wide.validate() }
    let progress = Widget("w", title: "W", symbol: "x", content: .progress(1.5, label: nil))
    #expect(throws: SurfaceValidationError.invalid("progress 1.5")) { try progress.validate() }
}

@Test func eventsReachTheAddOnInOrder() async throws {
    let seen = Seen()
    var handlers = AddOnHandlers()
    handlers.onEvent = { event in await seen.add(event) }
    let events = [
        SurfaceEvent(surface: Surface.settingsPage, control: "enabled", action: .toggled(false)),
        SurfaceEvent(surface: Surface.settingsPage, control: "city", action: .edited("Mumbai")),
        SurfaceEvent(surface: Surface.widget, widget: "moon", control: "next", action: .pressed)
    ]
    var messages: [SessionMessage] = [
        .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "moon", generation: 1),
        .request(id: 1, method: SessionProtocol.Method.activate, params: .null)
    ]
    for (offset, event) in events.enumerated() {
        messages.append(.request(id: 10 + offset, method: Surface.eventMethod, params: try JSONValue(encoding: event)))
    }
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for message in messages { continuation.yield(try! JSONEncoder().encode(message)) }
        continuation.finish()
    }
    let status = await AddOnSession.run(id: "moon", handlers: handlers, input: input) { _ in }
    #expect(status == 0)
    #expect(await seen.all == events)
}

private actor Seen {
    var all: [SurfaceEvent] = []
    func add(_ event: SurfaceEvent) { all.append(event) }
}

@Test func playerActionsAndAccountRowsValidate() throws {
    let heart = PlayerAction("like", label: "Like", symbol: "heart", selectedSymbol: "heart.fill", sources: ["com.spotify.client"])
    try PlayerAction.validate([heart])
    #expect(try JSONDecoder().decode([PlayerAction].self, from: JSONEncoder().encode([heart])) == [heart])
    #expect(throws: SurfaceValidationError.duplicateID("like")) { try PlayerAction.validate([heart, heart]) }
    var noSource = heart; noSource.sources = []
    #expect(throws: SurfaceValidationError.invalid("sources of like")) { try PlayerAction.validate([noSource]) }
    var badSource = heart; badSource.sources = ["com.spotify.client; rm"]
    #expect(throws: SurfaceValidationError.invalid("sources of like")) { try PlayerAction.validate([badSource]) }
    let many = (0..<5).map { PlayerAction("a\($0)", label: "A", symbol: "star", selectedSymbol: "star.fill", sources: ["x"]) }
    #expect(throws: (any Error).self) { try PlayerAction.validate(many) }
    try SettingsPage([SettingsSection("a", rows: [.account("spotify", "Spotify account", provider: "spotify")])]).validate()
    #expect(throws: SurfaceValidationError.invalid("account s")) {
        try SettingsPage([SettingsSection("a", rows: [.account("s", "S", provider: "")])]).validate()
    }
}

@Test func playerExtensionsValidate() throws {
    try PlayerExtension(sources: ["com.apple.Music"], menu: PlayerMenu("playlists", title: "Add to Playlist", symbol: "text.badge.plus"), queue: true).validate()
    #expect(throws: (any Error).self) { try PlayerExtension(sources: []).validate() }
    #expect(throws: (any Error).self) { try PlayerExtension(sources: ["x"], menu: PlayerMenu("m", title: "")).validate() }
    try PlayerQueueEntry.validate([PlayerQueueEntry(id: "a", title: "Song", artist: "", artworkURL: "https://example.com/a.jpg", storeID: "123")])
    #expect(throws: (any Error).self) { try PlayerQueueEntry.validate([PlayerQueueEntry(title: "Song", artist: "", artworkURL: "http://example.com/a.jpg")]) }
    #expect(throws: (any Error).self) { try PlayerQueueEntry.validate([PlayerQueueEntry(title: "Song", artist: "", storeID: "12a")]) }
    #expect(throws: (any Error).self) { try PlayerMenu.Item.validate([PlayerMenu.Item("", title: "x")]) }
}

@Test func liveActivitiesValidateAndRoundTrip() throws {
    let timer = LiveActivity("timer", symbol: "timer", text: "4:59", progress: .fraction(0.2), importance: .high)
    try LiveActivity.validate([timer])
    #expect(try JSONDecoder().decode([LiveActivity].self, from: JSONEncoder().encode([timer])) == [timer])
    #expect(LiveActivity.Importance.low < .normal && LiveActivity.Importance.normal < .high)
    #expect(throws: (any Error).self) { try LiveActivity.validate([timer, timer]) }
    #expect(throws: (any Error).self) { try LiveActivity.validate([LiveActivity("a", symbol: "x", text: String(repeating: "x", count: 61))]) }
    #expect(throws: (any Error).self) { try LiveActivity.validate([LiveActivity("a", symbol: "x", text: "y", progress: .fraction(2))]) }
    #expect(throws: (any Error).self) { try LiveActivity.validate([LiveActivity("a", symbol: "x", text: "y", lasts: 0)]) }
    #expect(throws: (any Error).self) {
        try LiveActivity.validate((0..<3).map { LiveActivity("a\($0)", symbol: "x", text: "y") })
    }
}

@Test func lockScreenRowsAndMenuBarTilesValidate() throws {
    let row = LockScreenRow(symbol: "timer", label: "Timer", value: "4:59")
    try row.validate()
    #expect(try JSONDecoder().decode(LockScreenRow.self, from: JSONEncoder().encode(row)) == row)
    #expect(throws: (any Error).self) { try LockScreenRow(symbol: "timer", label: "Timer", value: "").validate() }
    #expect(throws: (any Error).self) { try LockScreenRow(symbol: "timer", label: String(repeating: "x", count: 31), value: "1").validate() }
    let tile = MenuBarTile("start", symbol: "timer", title: "Start a timer", detail: "1 minute")
    try MenuBarTile.validate([tile])
    #expect(try JSONDecoder().decode([MenuBarTile].self, from: JSONEncoder().encode([tile])) == [tile])
    #expect(throws: SurfaceValidationError.duplicateID("start")) { try MenuBarTile.validate([tile, tile]) }
    #expect(throws: (any Error).self) { try MenuBarTile.validate((0..<3).map { MenuBarTile("t\($0)", symbol: "x", title: "T") }) }
    #expect(throws: (any Error).self) { try MenuBarTile.validate([MenuBarTile("t", symbol: "x", title: String(repeating: "x", count: 41))]) }
}

@Test func activityKindsAndSpokenValuesRoundTripAndAreChecked() throws {
    let timer = LiveActivity("podcast", symbol: "headphones", text: "4:59", importance: .attention, kind: .nowPlaying,
                             accessibilityValue: "4 minutes 59 seconds left")
    let decoded = try JSONDecoder().decode(LiveActivity.self, from: JSONEncoder().encode(timer))
    #expect(decoded == timer)
    // An activity from before 0.13 has neither field.
    let old = try JSONDecoder().decode(LiveActivity.self, from: Data(#"{"id":"a","symbol":"timer","text":"1:00","importance":"normal"}"#.utf8))
    #expect(old.kind == nil && old.accessibilityValue == nil)
    #expect(throws: SurfaceValidationError.self) {
        try LiveActivity.validate([LiveActivity("a", symbol: "timer", text: "1:00", accessibilityValue: String(repeating: "x", count: 121))])
    }
}

@Test func settingsButtonsCanAskFirstAndPagesHaveKeywords() throws {
    let page = SettingsPage([SettingsSection("notes", rows: [
        .button("clear", "Delete all notes", destructive: true,
                confirm: .init("Delete all notes?", message: "They go to the Trash.", confirmTitle: "Delete")),
    ])], keywords: ["markdown", "writing"])
    try page.validate()
    #expect(try JSONDecoder().decode(SettingsPage.self, from: JSONEncoder().encode(page)) == page)
    // A page from before 0.13 has neither.
    let old = try JSONDecoder().decode(SettingsPage.self, from: Data(#"{"sections":[]}"#.utf8))
    #expect(old.keywords == nil)
    let wrong = SettingsPage([SettingsSection("s", rows: [SettingsRow("t", title: "On", control: .toggle(isOn: true),
                                                                     confirm: .init("Sure?", confirmTitle: "Yes"))])])
    #expect(throws: SurfaceValidationError.self) { try wrong.validate() }
}

@Test func aWidgetIsSmallUnlessItSaysSo() throws {
    // Small sends exactly what a widget sent before sizes existed, so an older Ledge reads it the same.
    let small = Widget("w", title: "W", symbol: "x", content: .spacer)
    let json = String(decoding: try JSONEncoder().encode(small), as: UTF8.self)
    #expect(!json.contains("size"))
    let old = #"{"id":"w","title":"W","symbol":"x","content":{"spacer":{}}}"#
    #expect(try JSONDecoder().decode(Widget.self, from: Data(old.utf8)).size == .small)
}

@Test(arguments: Widget.Size.allCases)
func everyWidgetSizeRoundTrips(size: Widget.Size) throws {
    let widget = Widget("w", title: "W", symbol: "x", size: size, content: .text("Hi", style: nil))
    let back = try JSONDecoder().decode(Widget.self, from: try JSONEncoder().encode(widget))
    #expect(back == widget)
    #expect(back.size == size)
    try back.validate()
}
