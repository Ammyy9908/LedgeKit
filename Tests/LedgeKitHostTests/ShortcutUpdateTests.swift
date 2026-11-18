import Foundation
import LedgeKit
import LedgeKitHost
import Testing

@Test func shortcutsAreReadFromTheirTopicOnlyWhenDeclared() throws {
    let list = [AddOnShortcut("mute", title: "Mute microphones", key: "M")]
    let payload = try JSONValue(encoding: list)
    #expect(try SurfaceUpdate.read(topic: Surface.shortcutsTopic, payload: payload, declared: [Surface.shortcut]) == .shortcuts(list))
    #expect(throws: (any Error).self) { try SurfaceUpdate.read(topic: Surface.shortcutsTopic, payload: payload, declared: []) }
}
