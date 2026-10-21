import Foundation
import CoreFoundation
import CoreImage
import Vision

/// Bootstrap only: no shared sandbox, camera access, or long-lived credentials.
/// The extension reads this code from ReplayKit's consented screen stream.
struct BroadcastPairing: Codable {
    static let productionEndpoint = "https://reelproof-evidence.vercel.app"
    let kind: String
    let version: Int
    let server: String
    let token: String
    let acceptUntil: TimeInterval
    let nonce: String

    struct PairingError: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }
    static func isProductionServer(_ endpoint: String) -> Bool {
        endpoint == productionEndpoint || endpoint == productionEndpoint + "/"
    }
    static func create(token: String, now: TimeInterval = Date().timeIntervalSince1970) throws -> BroadcastPairing {
        let value = BroadcastPairing(kind: "reelproof-broadcast", version: 1, server: productionEndpoint,
            token: token, acceptUntil: now + 90, nonce: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        _ = try value.validated(now: now)
        return value
    }
    var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    var sessionExpiry: TimeInterval? {
        guard let payload = Self.jwtPart(token, index: 1), let number = payload["exp"] as? NSNumber else { return nil }
        return number.doubleValue
    }
    private static func jwtPart(_ token: String, index: Int) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var value = String(parts[index]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    func validated(now: TimeInterval = Date().timeIntervalSince1970) throws -> ServerConnection {
        // Never send captured frames to a server named by an arbitrary reel QR.
        // These shape checks are NOT signature verification; the pinned backend
        // must authenticate the JWT before any content leaves the extension.
        guard kind == "reelproof-broadcast", version == 1, server == Self.productionEndpoint,
              acceptUntil.isFinite, acceptUntil > now, acceptUntil <= now + 95,
              nonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              token.count <= 1536,
              let header = Self.jwtPart(token, index: 0), header["alg"] as? String == "HS256", header["typ"] as? String == "JWT",
              let claims = Self.jwtPart(token, index: 1), claims["aud"] as? String == "reelproof", claims["scope"] as? String == "analyze",
              let issued = claims["iat"] as? NSNumber, let expiry = claims["exp"] as? NSNumber,
              CFGetTypeID(issued) != CFBooleanGetTypeID(), CFGetTypeID(expiry) != CFBooleanGetTypeID(),
              issued.doubleValue.isFinite, expiry.doubleValue.isFinite,
              issued.doubleValue <= now + 30, issued.doubleValue >= now - 120,
              expiry.doubleValue > now + 5, expiry.doubleValue <= issued.doubleValue + 1800 else {
            throw PairingError(reason: "연결 QR이 만료되었거나 올바르지 않습니다. 앱에서 탐지 준비를 다시 누르세요.")
        }
        return ServerConnection(endpoint: server, token: token)
    }
    static func decode(_ text: String, now: TimeInterval = Date().timeIntervalSince1970) throws -> BroadcastPairing {
        guard text.utf8.count <= 2048, let data = text.data(using: .utf8) else { throw PairingError(reason: "연결 QR 형식 오류") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        _ = try value.validated(now: now)
        return value
    }
    func qrImage() -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(encoded, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)) else { return nil }
        // Vision on ReplayKit sees the rendered code; never request camera access.
        return CIContext().createCGImage(output, from: output.extent)
    }
}
