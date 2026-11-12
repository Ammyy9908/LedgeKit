import Foundation
import LedgeKit

// A countdown in every place an add-on can show something (LedgeKit 0.11.0).
//
// Its page picks a length and starts or stops it, and so does its row in the menu bar panel. While it runs, one
// activity counts down beside the notch with a progress ring, and a pill shows the time left on the lock screen;
// when it ends, a "done" activity shows for five seconds. Ledge's own activities come first, so the timer listens
// to where it's placed: while the user has turned its activities off it stops sending them, and if it ends where
// nobody can see it, it also says so with a notch message.

private let lengths: [(id: String, title: String, seconds: Double)] = [
    ("10s", "10 seconds", 10), ("1m", "1 minute", 60), ("5m", "5 minutes", 300),
    ("10m", "10 minutes", 600), ("25m", "25 minutes", 1500)
]

private actor Countdown {
    var length = "1m"
    var endsAt: Date?
    var placement: ActivityPlacement = .idle
    private var ticker: Task<Void, Never>?

    var seconds: Double { lengths.first { $0.id == length }?.seconds ?? 60 }

    func setLength(_ id: String) { if lengths.contains(where: { $0.id == id }) { length = id } }

    func start() {
        endsAt = Date().addingTimeInterval(seconds)
        ticker?.cancel()
        ticker = Task { await self.run() }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        endsAt = nil
        AddOnSession.show(activities: [])
        AddOnSession.show(lockScreenRow: nil)
        showTile()
    }

    /// The row in the menu bar panel: start a timer of the chosen length, or how long is left and a way to stop it.
    func showTile() {
        guard let endsAt else {
            let title = lengths.first { $0.id == length }?.title ?? "1 minute"
            AddOnSession.show(menuBarTiles: [MenuBarTile("toggle", symbol: "timer", title: "Start a timer", detail: title)])
            return
        }
        AddOnSession.show(menuBarTiles: [MenuBarTile("toggle", symbol: "stop.circle", title: "Timer · \(Self.clock(endsAt.timeIntervalSinceNow)) left",
                                                     detail: "Click to stop")])
    }

    var isRunning: Bool { endsAt != nil }

    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    func placed(_ placement: ActivityPlacement) {
        let wasOff = self.placement == .suppressed
        self.placement = placement
        // Turned back on: show where it's at straight away rather than waiting for the next second.
        if wasOff, placement != .suppressed { send() }
    }

    private func run() async {
        while let endsAt, !Task.isCancelled {
            if Date() >= endsAt {
                finish()
                return
            }
            send()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// The countdown everywhere it shows. The activity is left out while the user has turned activities off; the
    /// lock screen pill and the menu bar row only show when someone looks, so they're kept current.
    private func send() {
        guard let endsAt else { return }
        let left = max(0, endsAt.timeIntervalSinceNow)
        let text = Self.clock(left)
        AddOnSession.show(lockScreenRow: LockScreenRow(symbol: "timer", label: "Timer", value: text))
        showTile()
        guard placement != .suppressed else { return }
        AddOnSession.show(activities: [
            LiveActivity("countdown", symbol: "timer", text: text, progress: .fraction(min(1, max(0, 1 - left / seconds))), importance: .high)
        ])
    }

    private func finish() {
        let seen = placement == .center || placement == .side
        endsAt = nil
        ticker = nil
        AddOnSession.show(lockScreenRow: nil)
        showTile()
        AddOnSession.show(activities: [LiveActivity("done", symbol: "checkmark.circle.fill", text: "Timer done", importance: .high, lasts: 5)])
        // Waiting behind Ledge's own activities, or turned off: the end would go unseen, so say it in the notch too.
        if !seen { Task { try? await LedgeHost.notify(title: "Timer done", symbol: "timer") } }
        AddOnSession.log("Finished; it was \(placement.rawValue) at the end.")
    }

    func page() -> SettingsPage {
        let status: String
        switch (endsAt != nil, placement) {
        case (false, _): status = "Not running"
        case (true, .center), (true, .side): status = "Running, beside the notch"
        case (true, .outranked): status = "Running, waiting behind Ledge’s activities"
        case (true, .suppressed): status = "Running; its activities are turned off"
        case (true, .idle): status = "Running"
        }
        return SettingsPage([
            SettingsSection("timer", title: "Timer", footer: "The countdown shows beside the notch while nothing of Ledge’s own is showing there.", rows: [
                .picker("length", "Length", options: lengths.map { .init($0.id, $0.title) }, selected: length),
                .button(endsAt == nil ? "start" : "stop", endsAt == nil ? "Start" : "Stop"),
                .value("status", "Status", status)
            ])
        ])
    }
}

private let countdown = Countdown()
private func showPage() async { AddOnSession.show(await countdown.page()) }

var handlers = AddOnHandlers()
handlers.activate = {
    if let saved = try? await LedgeHost.value(String.self, forKey: "length") { await countdown.setLength(saved) }
    await showPage()
    await countdown.showTile()
}
handlers.deactivate = { await countdown.stop() }
handlers.onEvent = { event in
    switch (event.surface, event.control, event.action) {
    case (Surface.menuBarTile, "toggle", .pressed):
        if await countdown.isRunning { await countdown.stop() } else { await countdown.start() }
    case (_, "length", .picked(let id)):
        await countdown.setLength(id)
        try? await LedgeHost.set(id, forKey: "length")
        await countdown.showTile()
    case (_, "start", .pressed): await countdown.start()
    case (_, "stop", .pressed): await countdown.stop()
    default: break
    }
    await showPage()
}
handlers.onActivityPlacement = { change in
    await countdown.placed(change.placement)
    await showPage()
}
exit(await AddOnSession.run(id: "timer", handlers: handlers))
