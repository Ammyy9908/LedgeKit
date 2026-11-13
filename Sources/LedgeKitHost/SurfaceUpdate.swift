import LedgeKit

/// One surface an add-on sent, read the way Ledge reads it: decoded, checked against the surfaces the manifest
/// declares, and validated against Ledge's limits. Ledge draws what this returns; `ledgekit check` reports it. Both
/// use this one function, so the checker can't disagree with the app.
public enum SurfaceUpdate: Sendable, Equatable {
    case settingsPage(SettingsPage)
    case widgets([Widget])
    case playerActions([PlayerAction])
    case activities([LiveActivity])
    /// Nil takes it down.
    case lockScreenRow(LockScreenRow?)
    case menuBarTiles([MenuBarTile])
    /// Nil takes it down.
    case notchPage(NotchPage?)
    /// Nil takes it down.
    case player(PlayerExtension?)

    /// The surface name the topic belongs to, as `addon.json` lists it; nil for a topic Ledge doesn't know.
    public static func surface(forTopic topic: String) -> String? {
        switch topic {
        case Surface.settingsTopic: Surface.settingsPage
        case Surface.widgetsTopic: Surface.widget
        case Surface.playerActionsTopic: Surface.playerAction
        case Surface.activitiesTopic: Surface.activity
        case Surface.lockScreenRowTopic: Surface.lockScreenRow
        case Surface.menuBarTilesTopic: Surface.menuBarTile
        case Surface.notchPageTopic: Surface.notchPage
        case Surface.playerTopic: Surface.player
        default: nil
        }
    }

    /// Reads an update. Returns nil for a topic Ledge doesn't know, which it ignores; throws for one it refuses.
    public static func read(topic: String, payload: JSONValue, declared: Set<String>) throws -> SurfaceUpdate? {
        guard let surface = surface(forTopic: topic) else { return nil }
        guard declared.contains(surface) else { throw SurfaceValidationError.invalid("\(surface) isn't in the manifest's surfaces") }
        switch topic {
        case Surface.settingsTopic:
            let page = try payload.decode(SettingsPage.self)
            try page.validate()
            return .settingsPage(page)
        case Surface.widgetsTopic:
            let list = try payload.decode([Widget].self)
            guard list.count <= Surface.maximumWidgets, Set(list.map(\.id)).count == list.count
            else { throw SurfaceValidationError.invalid("widgets: at most \(Surface.maximumWidgets), each id once") }
            try list.forEach { try $0.validate() }
            return .widgets(list)
        case Surface.playerActionsTopic:
            let list = try payload.decode([PlayerAction].self)
            try PlayerAction.validate(list)
            return .playerActions(list)
        case Surface.activitiesTopic:
            let list = try payload.decode([LiveActivity].self)
            try LiveActivity.validate(list)
            return .activities(list)
        case Surface.lockScreenRowTopic:
            let row = payload == .null ? nil : try payload.decode(LockScreenRow.self)
            try row?.validate()
            return .lockScreenRow(row)
        case Surface.menuBarTilesTopic:
            let list = try payload.decode([MenuBarTile].self)
            try MenuBarTile.validate(list)
            return .menuBarTiles(list)
        case Surface.notchPageTopic:
            let page = payload == .null ? nil : try payload.decode(NotchPage.self)
            try page?.validate()
            return .notchPage(page)
        case Surface.playerTopic:
            let player = payload == .null ? nil : try payload.decode(PlayerExtension.self)
            try player?.validate()
            return .player(player)
        default:
            return nil
        }
    }
}
