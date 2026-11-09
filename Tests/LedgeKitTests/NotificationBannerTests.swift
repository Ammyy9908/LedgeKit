import Testing
@testable import LedgeKit

@Test func notificationPrivacyAndBounds() {
    let hidden = NotificationBannerResponse(request: .init(title: "Messages", body: "Private text", showPreview: false))
    #expect(hidden.text == "Messages: New notification")
    let long = NotificationBannerResponse(request: .init(title: String(repeating: "a", count: 500), body: String(repeating: "b", count: 500), showPreview: true))
    #expect(long.text.count == 758)
}
