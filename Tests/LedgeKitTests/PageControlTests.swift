import Foundation
import Testing
@testable import LedgeKit

@Test func nativeControlsRoundTripAndKeepOldPagesCompatible() throws {
    let node = PageNode.vstack(spacing: 6, children: [
        .control(PageButton("mode", title: "Scientific", role: .selected)),
        .readout(PageReadout("expression", expression: "249 * 12", value: "2,988", copyControl: "result")),
        .buttonGrid(columns: 2, rowHeight: 30, buttons: [PageButton("seven", title: "7"), PageButton("divide", title: "÷", role: .accent)]),
    ])
    let page = NotchPage(title: "Math", symbol: "plus", size: .large, preferredWidth: 680, screen: PageScreen("main", content: node))
    try page.validate()
    #expect(try JSONDecoder().decode(NotchPage.self, from: JSONEncoder().encode(page)) == page)
    let history = PageNode.list(id: "history", rows: [ListRow("a", title: "249 × 12", subtitle: "2,988", emphasizesSubtitle: true)])
    try PageScreen("history", content: history).validate()
    #expect(history.hasNativeControls)
    #expect(try JSONDecoder().decode(PageNode.self, from: JSONEncoder().encode(history)) == history)
    let old = #"{"title":"Old","symbol":"x","size":"small","screen":{"id":"a","depth":0,"back":false,"actions":[],"content":{"text":{"_0":"Hello"}}}}"#
    #expect(try JSONDecoder().decode(NotchPage.self, from: Data(old.utf8)).preferredWidth == nil)
}

@Test func nativeControlLimitsRejectMalformedAndDuplicateControls() throws {
    for node in [PageNode.buttonGrid(columns: 0, rowHeight: 30, buttons: [PageButton("a", title: "A")]),
                 .buttonGrid(columns: 11, rowHeight: 30, buttons: [PageButton("a", title: "A")]),
                 .buttonGrid(columns: 2, rowHeight: .nan, buttons: [PageButton("a", title: "A")]),
                 .buttonGrid(columns: 1, rowHeight: 30, buttons: [PageButton("a", title: "A"), PageButton("a", title: "Again")]),
                 .readout(PageReadout("a", expression: "", value: "0", copyControl: "a"))] {
        #expect(throws: (any Error).self) { try PageScreen("main", content: node).validate() }
    }
    var page = NotchPage(title: "Math", symbol: "plus", preferredWidth: .infinity, screen: PageScreen("main", content: .text("0", style: nil)))
    #expect(throws: (any Error).self) { try page.validate() }
    page.preferredWidth = 10
    #expect(throws: (any Error).self) { try page.validate() }
}

@Test func tapesDisplaysAndTintsRoundTripAndNeed026() throws {
    let node = PageNode.vstack(spacing: 8, children: [
        .control(PageButton("focus", title: "Focus", role: .selected, tint: .blue)),
        .tape(PageTape("length", value: 25, minimum: 1, maximum: 480, tint: .blue, accessibilityLabel: "Length in minutes")),
        .display("25:00", tint: .blue),
    ])
    try PageScreen("main", content: node).validate()
    #expect(try JSONDecoder().decode(PageNode.self, from: JSONEncoder().encode(node)) == node)
    #expect(node.needsTapeOrTint)
    #expect(!PageNode.control(PageButton("a", title: "A", role: .accent)).needsTapeOrTint)
    // A 0.23 button, without a tint, still decodes.
    let old = #"{"id":"a","title":"A","role":"accent"}"#
    #expect(try JSONDecoder().decode(PageButton.self, from: Data(old.utf8)).tint == nil)
}

@Test func malformedTapesAndDisplaysAreRejected() {
    for node in [PageNode.tape(PageTape("t", value: 0, minimum: 1, maximum: 10, accessibilityLabel: "Length")),
                 .tape(PageTape("t", value: 5, minimum: 10, maximum: 10, accessibilityLabel: "Length")),
                 .tape(PageTape("t", value: 5, minimum: 1, maximum: 10, labelEvery: 0, accessibilityLabel: "Length")),
                 .tape(PageTape("t", value: 5, minimum: 1, maximum: 10, accessibilityLabel: "")),
                 .hstack(spacing: nil, children: [.tape(PageTape("t", value: 5, minimum: 1, maximum: 10, accessibilityLabel: "L")),
                                                  .control(PageButton("t", title: "Again"))]),
                 .display("", tint: nil),
                 .display(String(repeating: "9", count: 21), tint: nil)] {
        #expect(throws: (any Error).self) { try PageScreen("main", content: node).validate() }
    }
}

@Test func ringsRoundTripNeed027AndRejectBadValues() throws {
    let ring = PageNode.hstack(spacing: 12, children: [
        .ring(PageRing(value: 0.06, symbol: "sparkle", title: "Codex", caption: "6% left", tint: .red,
                       accessibilityLabel: "Codex, weekly limit, 6% left")),
        .ring(PageRing(value: nil, symbol: "person", title: "Cursor", accessibilityLabel: "Cursor, not signed in")),
    ])
    try PageScreen("main", content: ring).validate()
    #expect(try JSONDecoder().decode(PageNode.self, from: JSONEncoder().encode(ring)) == ring)
    #expect(ring.needsRingLabelOrPanel)
    #expect(!PageNode.display("1", tint: nil).needsRingLabelOrPanel)
    for bad in [PageRing(value: 1.5, title: "A", accessibilityLabel: "A"),
                PageRing(value: 0.5, title: "", accessibilityLabel: "A"),
                PageRing(value: 0.5, title: "A", accessibilityLabel: ""),
                PageRing(value: 0.5, image: Data([1, 2, 3]), title: "A", accessibilityLabel: "A")] {
        #expect(throws: (any Error).self) { try PageScreen("main", content: .ring(bad)).validate() }
    }
}

@Test func labelsPanelsAndPressableRingsRoundTripAndValidate() throws {
    let card = PageNode.vstack(spacing: 6, children: [
        .label(PageLabel("Working", symbol: "circle.fill", tint: .orange)),
        .label(PageLabel("Ran swift test", symbol: "checkmark", tint: .orange, tintsText: false)),
        .panel(.text("swift build", style: nil)),
        .ring(PageRing(id: "ring-codex", value: 0.05, title: "Codex", accessibilityLabel: "Codex, 5% left")),
    ])
    try PageScreen("main", content: card).validate()
    #expect(try JSONDecoder().decode(PageNode.self, from: JSONEncoder().encode(card)) == card)
    #expect(PageNode.panel(.spacer).needsRingLabelOrPanel)
    // A ring from 0.27 without an id still decodes.
    let old = #"{"value":0.5,"title":"A","accessibilityLabel":"A"}"#
    #expect(try JSONDecoder().decode(PageRing.self, from: Data(old.utf8)).id == nil)
    for bad: PageNode in [.label(PageLabel("")), .label(PageLabel(String(repeating: "a", count: 201))),
                          .panel(.button(id: "", title: "A", symbol: nil)),
                          .hstack(spacing: nil, children: [.ring(PageRing(id: "x", value: 0, title: "A", accessibilityLabel: "A")),
                                                           .button(id: "x", title: "B", symbol: nil)])] {
        #expect(throws: (any Error).self) { try PageScreen("main", content: bad).validate() }
    }
}

@Test func aSelectedHeaderButtonRoundTripsAndOldOnesDecode() throws {
    let action = PageAction("usage", symbol: "gauge", label: "Usage", selected: true)
    #expect(try JSONDecoder().decode(PageAction.self, from: JSONEncoder().encode(action)).selected)
    let tinted = PageAction("sessions", symbol: "checklist", label: "Sessions", tint: .orange)
    #expect(try JSONDecoder().decode(PageAction.self, from: JSONEncoder().encode(tinted)) == tinted)
    let old = #"{"id":"a","symbol":"gear","label":"A","destructive":false}"#
    #expect(try !JSONDecoder().decode(PageAction.self, from: Data(old.utf8)).selected)
}
