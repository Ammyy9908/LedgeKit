import Foundation

/// Version 1 of the local add-on protocol. Each invocation handles one request.
public struct AddOnRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let operation: String
    public let trackID: String
    public let liked: Bool?
    public let accessToken: String

    public init(operation: String, trackID: String, liked: Bool?, accessToken: String) {
        protocolVersion = 1
        self.operation = operation
        self.trackID = trackID
        self.liked = liked
        self.accessToken = accessToken
    }
}

public struct AddOnResponse: Codable, Sendable {
    public let value: Bool?
    public let error: String?
    public init(value: Bool?, error: String? = nil) {
        self.value = value
        self.error = error
    }
}
