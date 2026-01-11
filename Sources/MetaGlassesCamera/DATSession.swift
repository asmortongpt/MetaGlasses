import Foundation

// Placeholder for DATSession to allow compilation without Meta SDK
// In production, this would come from MetaWearablesDAT framework

public class DATSession {
    public static var shared: DATSession = DATSession()
    public weak var delegate: DATSessionDelegate?

    public func connect() async throws {
        // Placeholder
    }

    public func disconnect() async {
        // Placeholder
    }

    public func capturePhoto() async throws -> Data {
        // Placeholder
        return Data()
    }
}

@MainActor
public protocol DATSessionDelegate: AnyObject {
    func sessionDidConnect(_ session: DATSession)
    func sessionDidDisconnect(_ session: DATSession, error: Error?)
    func session(_ session: DATSession, didFailWithError error: Error)
}
