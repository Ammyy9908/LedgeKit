import Foundation

/// Input to a notification-banners worker. The host obtains consent before supplying visible banner text.
/// No authentication tokens, history, reply actions or arbitrary host operations are exposed.
public struct NotificationBannerRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let title: String
    public let body: String
    public let showPreview: Bool
    public init(title: String, body: String, showPreview: Bool) {
        protocolVersion = 1
        self.title = title
        self.body = body
        self.showPreview = showPreview
    }
}

/// A compact, bounded notification for the host-owned notch surface.
public struct NotificationBannerResponse: Codable, Sendable {
    public let text: String
    public init(request: NotificationBannerRequest) {
        let title = String(request.title.prefix(256))
        let body = request.showPreview ? String(request.body.prefix(8192)) : "New notification"
        text = [title, body].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}
