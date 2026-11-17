import Foundation
import Testing
import LedgeKit

private let phone = ShareDestination("pixel", title: "Pixel 9", subtitle: "Phone · 192.168.1.20", symbol: "iphone")

@Test func shareTargetsWithinLimitsPass() throws {
    try ShareTarget(title: "LocalSend", symbol: "paperplane", destinations: [phone], emptyNote: "No devices nearby").validate()
    try ShareTarget(title: "LocalSend", destinations: []).validate()
}

@Test func shareTargetsOutsideLimitsAreRefused() {
    #expect(throws: (any Error).self) { try ShareTarget(title: "", destinations: []).validate() }
    #expect(throws: (any Error).self) { try ShareTarget(title: "LocalSend", destinations: [phone, phone]).validate() }
    #expect(throws: (any Error).self) { try ShareTarget(title: "LocalSend", destinations: [ShareDestination("", title: "x")]).validate() }
    let many = (0...Surface.maximumShareDestinations).map { ShareDestination("d\($0)", title: "Device") }
    #expect(throws: (any Error).self) { try ShareTarget(title: "LocalSend", destinations: many).validate() }
}

@Test func sharedFilesNeedADestinationAndAbsolutePaths() throws {
    try SharedFiles(destination: "pixel", files: ["/Users/sam/a.png"]).validate()
    #expect(throws: (any Error).self) { try SharedFiles(destination: "pixel", files: []).validate() }
    #expect(throws: (any Error).self) { try SharedFiles(destination: "pixel", files: ["a.png"]).validate() }
    #expect(throws: (any Error).self) { try SharedFiles(destination: "", files: ["/a.png"]).validate() }
}

@Test func questionsHaveBoundedTimeouts() throws {
    try HostQuestion(title: "Accept 3 files from Pixel 9?", message: "a.png, b.png, c.pdf · 4 MB", accept: "Accept").validate()
    #expect(throws: (any Error).self) { try HostQuestion(title: "Accept?", accept: "Accept", timeout: 600).validate() }
    #expect(throws: (any Error).self) { try HostQuestion(title: "", accept: "Accept").validate() }
}

@Test func rowsThatTakeFilesSayItAndOldRowsStillRead() throws {
    let row = ListRow("pixel", title: "Pixel 9", acceptsFiles: true)
    #expect(try JSONDecoder().decode(ListRow.self, from: JSONEncoder().encode(row)) == row)
    // A row from an older add-on has no acceptsFiles, and a plain row doesn't write one.
    let old = try JSONDecoder().decode(ListRow.self, from: Data(#"{"id":"n1","title":"Note"}"#.utf8))
    #expect(old.acceptsFiles == nil)
    #expect(!String(decoding: try JSONEncoder().encode(ListRow("n1", title: "Note")), as: UTF8.self).contains("acceptsFiles"))
    let page = PageNode.vstack(spacing: nil, children: [.text("Nearby", style: nil), .list(id: "devices", rows: [row])])
    #expect(page.listRows.map(\.id) == ["pixel"])
}

@Test func aShareTargetNeedsTheSharedFilesCapability() throws {
    func manifest(_ capabilities: [String]) -> AddOnManifest {
        AddOnManifest(id: "localsend", version: "0.1.0", protocolVersion: 2, name: "LocalSend", summary: "s", description: "d",
                      author: "a", capabilities: capabilities, executable: "LocalSend", surfaces: [Surface.shareTarget])
    }
    #expect(throws: (any Error).self) { try manifest([]).validate() }
    try manifest([Surface.sharedFilesCapability]).validate()
}

private actor Shares {
    var all: [SharedFiles] = []
    func add(_ files: SharedFiles) { all.append(files) }
}

@Test func sharedFilesReachTheAddOnAndBadOnesDont() async throws {
    let shares = Shares()
    var handlers = AddOnHandlers()
    handlers.onShare = { await shares.add($0) }
    let good = SharedFiles(destination: "pixel", files: ["/Users/sam/a.png", "/Users/sam/b.pdf"])
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for message: SessionMessage in [
            .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "localsend", generation: 1),
            .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
            .request(id: 2, method: Surface.sharedMethod, params: try! JSONValue(encoding: good)),
            .request(id: 3, method: Surface.sharedMethod, params: try! JSONValue(encoding: SharedFiles(destination: "pixel", files: ["relative.png"]))),
        ] { continuation.yield(try! JSONEncoder().encode(message)) }
        continuation.finish()
    }
    let status = await AddOnSession.run(id: "localsend", handlers: handlers, input: input) { _ in }
    #expect(status == 0)
    #expect(await shares.all == [good])
}
