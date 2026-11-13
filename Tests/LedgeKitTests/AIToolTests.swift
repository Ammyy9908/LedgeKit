import Foundation
import Testing
import LedgeKit

private let addNote = AddOnTool("add_note", title: "Add a note", summary: "Adds a note with the given text and returns its title.",
                                arguments: [.init("text", summary: "The note, in Markdown.", kind: .text(maximumLength: 2000)),
                                            .init("pinned", summary: "Pin it to the top.", kind: .boolean, required: false)])

@Test func toolsWithinLedgesLimitsPass() throws {
    try AddOnTool.validate([addNote, AddOnTool("count", title: "Count", summary: "How many notes there are.")])
}

@Test func toolsOutsideLedgesLimitsAreRefused() {
    #expect(throws: (any Error).self) { try AddOnTool.validate([AddOnTool("Add-Note", title: "A", summary: "B")]) }
    #expect(throws: (any Error).self) { try AddOnTool.validate([addNote, addNote]) }
    #expect(throws: (any Error).self) { try AddOnTool.validate((0..<17).map { AddOnTool("t\($0)", title: "T", summary: "S") }) }
    #expect(throws: (any Error).self) { try AddOnTool.validate([AddOnTool("x", title: "", summary: "S")]) }
    #expect(throws: (any Error).self) {
        try AddOnTool.validate([AddOnTool("x", title: "X", summary: "S", arguments: [.init("c", summary: "C", kind: .choice([]))])])
    }
}

@Test func argumentsAreCheckedAgainstTheTool() throws {
    let ok = try addNote.check(.object(["text": .string("Oat milk")]))
    #expect(ok["text"] == .string("Oat milk"))
    #expect(throws: AddOnError.self) { _ = try addNote.check(.object([:])) }
    #expect(throws: AddOnError.self) { _ = try addNote.check(.object(["text": .number(3)])) }
    #expect(throws: AddOnError.self) { _ = try addNote.check(.object(["text": .string("a"), "path": .string("/etc")])) }
    #expect(throws: AddOnError.self) { _ = try addNote.check(.object(["text": .string(String(repeating: "a", count: 2001))])) }
    #expect(throws: AddOnError.self) { _ = try addNote.check(.string("hello")) }
    let page = AddOnTool("page", title: "Page", summary: "S", arguments: [.init("n", summary: "N", kind: .number(minimum: 1, maximum: 10, whole: true))])
    #expect(throws: AddOnError.self) { _ = try page.check(.object(["n": .number(2.5)])) }
    #expect(throws: AddOnError.self) { _ = try page.check(.object(["n": .number(11)])) }
    #expect(try page.check(.object(["n": .number(3)]))["n"] == .number(3))
}

@Test func theSchemaIsWhatAnMCPClientReads() {
    guard case let .object(schema) = addNote.inputSchema, case let .object(properties)? = schema["properties"] else { Issue.record("no schema"); return }
    #expect(schema["required"] == .array([.string("text")]))
    #expect(schema["additionalProperties"] == .bool(false))
    #expect(properties["pinned"] == .object(["type": .string("boolean"), "description": .string("Pin it to the top.")]))
}

@Test func aToolRoundTripsAndDefaultsToNotDestructive() throws {
    let back = try JSONDecoder().decode(AddOnTool.self, from: JSONEncoder().encode(addNote))
    #expect(back == addNote)
    let minimal = #"{"name":"count","title":"Count","summary":"How many."}"#
    let decoded = try JSONDecoder().decode(AddOnTool.self, from: Data(minimal.utf8))
    #expect(decoded.arguments.isEmpty && !decoded.destructive)
}

@Test func resultsOverTheLimitAreRefused() throws {
    try ToolResult.text("Added.").validate()
    #expect(throws: (any Error).self) { try ToolResult.text(String(repeating: "a", count: 70_000)).validate() }
}

@Test func resultsEncodePlainly() throws {
    #expect(String(decoding: try JSONEncoder().encode(ToolResult.text("Added.")), as: UTF8.self) == #"{"text":"Added."}"#)
    let json = ToolResult.json(.object(["count": .number(3)]))
    #expect(try JSONDecoder().decode(ToolResult.self, from: JSONEncoder().encode(json)) == json)
}
