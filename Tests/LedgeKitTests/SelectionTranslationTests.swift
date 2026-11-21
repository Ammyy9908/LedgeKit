import Foundation
import Testing
@testable import LedgeKit

@Test func translationOptionsRoundTripAndDefaultToNoSelectionMonitoring() throws {
    let options = SelectionTranslation(target: "en", secondary: "es")
    #expect(!options.selectionButton)
    #expect(try JSONDecoder().decode(SelectionTranslation.self, from: JSONEncoder().encode(options)) == options)
    try options.validate()
}

@Test func translationOptionsRejectInvalidAndEquivalentLanguages() {
    for pair in [("", "es"), ("en", "en-US"), ("en/../../", "es"), (String(repeating: "a", count: 80), "es")] {
        #expect(throws: SurfaceValidationError.self) { try SelectionTranslation(target: pair.0, secondary: pair.1).validate() }
    }
}
