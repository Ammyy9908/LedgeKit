import LedgeKit

extension AddOnManifest {
    /// Validates a manifest for this host. Since LedgeKit 0.4.0 capabilities are open, so this is the SDK's own
    /// check; whether a capability is granted is the registry's decision (`AddOnRegistry.grantedCapabilities`).
    public func validateForLedgeHost() throws {
        try validate()
    }
}
