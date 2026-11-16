import Foundation
import Testing
import LedgeKit

private let heart = PickerItem("2764", text: "❤️", label: "red heart", keywords: ["love", "like"])
private let grin = PickerItem("1f600", text: "😀", label: "grinning face", keywords: ["smile", "happy"])

@Test func searchMatchesTheStartOfWords() {
    #expect(heart.matches("hea"))
    #expect(heart.matches("red hea"))
    #expect(heart.matches("LOVE"))
    #expect(heart.matches("   "))
    #expect(!heart.matches("eart"))
    #expect(!heart.matches("heart smile"))
    #expect(grin.matches("face sm"))
}

@Test func pickersWithinLimitsPass() throws {
    try Picker(title: "Emoji", placeholder: "Search emoji",
               sections: [.init("recents", title: "Recents", symbol: "clock", items: [heart]),
                          .init("smileys", title: "Smileys", items: [grin, heart])]).validate()
}

@Test func pickersOutsideLimitsAreRefused() {
    func picker(_ sections: [Picker.Section], title: String = "Emoji") -> Picker {
        Picker(title: title, placeholder: "Search", sections: sections)
    }
    #expect(throws: (any Error).self) { try picker([], title: "").validate() }
    #expect(throws: (any Error).self) { try picker([.init("a", title: "A", items: []), .init("a", title: "B", items: [])]).validate() }
    #expect(throws: (any Error).self) { try picker([.init("a", title: "A", items: [heart, heart])]).validate() }
    #expect(throws: (any Error).self) { try picker([.init("a", title: "A", items: [PickerItem("x", text: "", label: "Empty")])]).validate() }
    let many = (0..<5001).map { PickerItem("i\($0)", text: "x", label: "x") }
    #expect(throws: (any Error).self) { try picker([.init("a", title: "A", items: many)]).validate() }
}

@Test func aPickerRoundTrips() throws {
    let picker = Picker(title: "Snippets", placeholder: "Search snippets", style: .rows,
                        sections: [.init("all", title: "All", items: [PickerItem("sig", text: "Best,\nSam", label: "Signature")])])
    #expect(try JSONDecoder().decode(Picker.self, from: JSONEncoder().encode(picker)) == picker)
}

private actor Picks {
    var items: [PickedItem] = []
    func add(_ item: PickedItem) { items.append(item) }
}

@Test func aPickReachesTheAddOn() async throws {
    let picks = Picks()
    var handlers = AddOnHandlers()
    handlers.onPicked = { await picks.add($0) }
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for message: SessionMessage in [
            .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "emoji", generation: 1),
            .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
            .request(id: 2, method: Surface.pickedMethod, params: try! JSONValue(encoding: PickedItem(section: "smileys", id: "1f600"))),
        ] { continuation.yield(try! JSONEncoder().encode(message)) }
        continuation.finish()
    }
    let status = await AddOnSession.run(id: "emoji", handlers: handlers, input: input) { _ in }
    #expect(status == 0)
    #expect(await picks.items == [PickedItem(section: "smileys", id: "1f600")])
}
