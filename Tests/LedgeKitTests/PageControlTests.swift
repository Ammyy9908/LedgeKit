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
