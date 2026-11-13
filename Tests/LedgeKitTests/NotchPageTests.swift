import Foundation
import Testing
import LedgeKit

// A notch page like a notes add-on's: a list screen, and a note screen with an editor.

private let listScreen = PageScreen("list", title: "Notes",
    actions: [PageAction("new", symbol: "square.and.pencil", label: "New note")],
    content: .list(id: "notes", rows: [
        ListRow("n1", title: "Launch day", subtitle: "Beta 2 goes out at 10:00", detail: "12:41 PM"),
        ListRow("n2", title: "Groceries", subtitle: "Oat milk, eggs, basil", detail: "Yesterday"),
    ]))

private let noteScreen = PageScreen("note-n1", depth: 1, caption: "Edited 11:35 PM", back: true,
    actions: [PageAction("copy", symbol: "doc.on.doc", label: "Copy note"),
              PageAction("delete", symbol: "trash", label: "Delete note", destructive: true)],
    content: .editor(id: "body", text: "# Launch day\n- [ ] Beta 2\n- [x] Notes", placeholder: "Start writing", autofocus: true))

private let emptyScreen = PageScreen("list", title: "Notes",
    actions: [PageAction("new", symbol: "square.and.pencil", label: "New note")],
    content: .empty(symbol: "square.and.pencil", title: "No notes yet", detail: nil))

@Test func notchPagesValidateAndRoundTrip() throws {
    for screen in [listScreen, noteScreen, emptyScreen] {
        let page = NotchPage(title: "Notes", symbol: "note.text", size: .medium, screen: screen)
        try page.validate()
        #expect(try JSONDecoder().decode(NotchPage.self, from: JSONEncoder().encode(page)) == page)
    }
}

@Test func pageEventsCarryTheirScreenAndRow() throws {
    let events = [
        SurfaceEvent(surface: Surface.notchPage, control: "notes", action: .pressed, screen: "list", item: "n1"),
        SurfaceEvent(surface: Surface.notchPage, control: PageScreen.backControl, action: .pressed, screen: "note-n1"),
        SurfaceEvent(surface: Surface.notchPage, control: "body", action: .edited("# Launch"), screen: "note-n1"),
        SurfaceEvent(surface: Surface.notchPage, control: "body", action: .ended("# Launch day"), screen: "note-n1"),
    ]
    for event in events {
        #expect(try JSONDecoder().decode(SurfaceEvent.self, from: JSONEncoder().encode(event)) == event)
    }
    // An event from an older Ledge, without the new fields, still decodes.
    let old = #"{"surface":"widget","widget":"moon","control":"next","action":{"pressed":{}}}"#
    let decoded = try JSONDecoder().decode(SurfaceEvent.self, from: Data(old.utf8))
    #expect(decoded.screen == nil && decoded.item == nil && decoded.action == .pressed)
}

@Test func invalidScreensAreRefused() {
    func check(_ screen: PageScreen) throws { try NotchPage(title: "Notes", symbol: "note.text", screen: screen).validate() }

    // The back button's id is taken while the screen has one.
    #expect(throws: SurfaceValidationError.duplicateID("back")) {
        try check(PageScreen("s", back: true, actions: [PageAction("back", symbol: "chevron.left", label: "Back")], content: .spacer))
    }
    // Ids are unique across the header and the content.
    #expect(throws: SurfaceValidationError.duplicateID("new")) {
        try check(PageScreen("s", actions: [PageAction("new", symbol: "plus", label: "New")],
                             content: .button(id: "new", title: "New", symbol: nil)))
    }
    #expect(throws: SurfaceValidationError.invalid("more than one editor on a screen")) {
        try check(PageScreen("s", content: .vstack(spacing: nil, children: [
            .editor(id: "a", text: "", placeholder: nil, autofocus: false),
            .editor(id: "b", text: "", placeholder: nil, autofocus: false),
        ])))
    }
    #expect(throws: SurfaceValidationError.tooLarge("editor text over \(Surface.maximumEditorText) characters")) {
        try check(PageScreen("s", content: .editor(id: "a", text: String(repeating: "x", count: Surface.maximumEditorText + 1),
                                                    placeholder: nil, autofocus: false)))
    }
    let tooManyRows = (0...Surface.maximumListRows).map { ListRow("r\($0)", title: "Row") }
    #expect(throws: SurfaceValidationError.tooLarge("\(tooManyRows.count) rows in list l")) {
        try check(PageScreen("s", content: .list(id: "l", rows: tooManyRows)))
    }
    #expect(throws: SurfaceValidationError.duplicateID("r")) {
        try check(PageScreen("s", content: .list(id: "l", rows: [ListRow("r", title: "A"), ListRow("r", title: "B")])))
    }
    #expect(throws: SurfaceValidationError.tooLarge("4 header buttons")) {
        try check(PageScreen("s", actions: (0..<4).map { PageAction("a\($0)", symbol: "star", label: "A") }, content: .spacer))
    }
    #expect(throws: SurfaceValidationError.invalid("screen depth 17")) { try check(PageScreen("s", depth: 17, content: .spacer)) }
    #expect(throws: SurfaceValidationError.invalid("notch page title")) {
        try NotchPage(title: "", symbol: "note.text", screen: listScreen).validate()
    }
    let tooManyParts = PageNode.vstack(spacing: nil, children: Array(repeating: .spacer, count: Surface.maximumPageNodes))
    #expect(throws: SurfaceValidationError.tooLarge("more than \(Surface.maximumPageNodes) parts")) {
        try check(PageScreen("s", content: tooManyParts))
    }
}

/// `show(notchPage:)` sends the page as JSON on its topic, and nil as null, which takes the page down.
@Test func pagesEncodeForTheirTopicAndNilTakesThemDown() throws {
    let page = NotchPage(title: "Notes", symbol: "note.text", size: .large, screen: noteScreen)
    let payload = try JSONValue(encoding: page)
    #expect(try payload.decode(NotchPage.self) == page)
    #expect(try JSONValue(encoding: Optional<NotchPage>.none) == .null)
    #expect(Surface.notchPageTopic == "surface.notch-page")
    #expect(Surface.notchPage == "notch-page")
}
