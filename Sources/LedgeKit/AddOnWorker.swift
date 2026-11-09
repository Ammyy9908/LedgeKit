import Foundation

/// One-request worker for the legacy version-1 transport.
/// The host closes stdin after its JSON request. stdout is reserved for one response.
public enum AddOnWorker {
    public static let maximumRequestBytes = 65_536

    /// Decodes a bounded request and calls the implementation. Errors never expose
    /// exception text, which may contain credentials or provider response bodies.
    public static func respond(
        to data: Data,
        handler: @Sendable (AddOnRequest) async throws -> AddOnResponse
    ) async -> AddOnResponse {
        guard data.count <= maximumRequestBytes else {
            return AddOnResponse(value: nil, error: "Request exceeds the size limit.")
        }
        do {
            let request = try JSONDecoder().decode(AddOnRequest.self, from: data)
            guard request.protocolVersion == 1 else {
                return AddOnResponse(value: nil, error: "Unsupported protocol version.")
            }
            return try await handler(request)
        } catch {
            return AddOnResponse(value: nil, error: "Add-on could not complete the request.")
        }
    }

    /// Runs once against standard input/output. This is not a persistent lifecycle
    /// runtime or sandbox. Diagnostic logging must use stderr and omit credentials.
    public static func run(
        handler: @Sendable (AddOnRequest) async throws -> AddOnResponse
    ) async {
        var input = Data()
        do {
            while let chunk = try FileHandle.standardInput.read(upToCount: min(4096, maximumRequestBytes + 1 - input.count)),
                  !chunk.isEmpty {
                input.append(chunk)
                if input.count > maximumRequestBytes { break }
            }
            let response = await respond(to: input, handler: handler)
            try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(response))
        } catch {
            // A closed transport cannot receive a response. Never print exception data.
        }
    }
}
