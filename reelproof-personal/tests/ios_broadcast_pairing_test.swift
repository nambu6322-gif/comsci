import Foundation
import CoreGraphics
import CoreImage
import Vision

@main struct BroadcastPairingTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
    static func token(now: TimeInterval, expiry: TimeInterval? = nil, scope: String = "analyze", algorithm: String = "HS256") -> String {
        func encode(_ value: [String: Any]) -> String {
            try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return encode(["alg":algorithm,"typ":"JWT"]) + "." + encode(["aud":"reelproof","scope":scope,"iat":Int(now),"exp":expiry ?? now+1800,"jti":"0123456789abcdef0123456789abcdef"]) + ".fixture-not-a-valid-signature"
    }
    static func reject(_ pairing: BroadcastPairing, now: TimeInterval, _ message: String) {
        expect((try? pairing.validated(now: now)) == nil, message)
    }
    static func main() throws {
        let now = floor(Date().timeIntervalSince1970)
        let good = try BroadcastPairing.create(token: token(now: now), now: now)
        let value = try good.validated(now: now)
        expect(value.endpoint == BroadcastPairing.productionEndpoint && value.valid, "Pinned HTTPS endpoint")
        expect(try BroadcastPairing.decode(String(data:good.encoded,encoding:.utf8)!,now:now).nonce == good.nonce, "Round-trip")
        reject(good,now:now+91,"Reject expired QR")
        for endpoint in ["https://evil.example", "http://reelproof-evidence.vercel.app", "https://reelproof-evidence.vercel.app.evil.example", "https://reelproof-evidence.vercel.app:444", "https://user@reelproof-evidence.vercel.app", "https://reelproof-evidence.vercel.app/?next=evil", "https://reelproof-evidence.vercel.app/path"] {
            reject(BroadcastPairing(kind:good.kind,version:1,server:endpoint,token:good.token,acceptUntil:good.acceptUntil,nonce:good.nonce),now:now,"Reject arbitrary QR endpoint")
        }
        for credential in [token(now:now,scope:"admin"),token(now:now,algorithm:"none"),token(now:now,expiry:now-1),token(now:now,expiry:now+3600),token(now:now-180),token(now:now+60),"long-lived-app-key-is-not-a-JWT"] {
            reject(BroadcastPairing(kind:good.kind,version:1,server:good.server,token:credential,acceptUntil:good.acceptUntil,nonce:good.nonce),now:now,"Reject unsafe token shape/lifetime")
        }
        reject(BroadcastPairing(kind:good.kind,version:2,server:good.server,token:good.token,acceptUntil:good.acceptUntil,nonce:good.nonce),now:now,"Reject unsupported version")
        reject(BroadcastPairing(kind:good.kind,version:1,server:good.server,token:good.token,acceptUntil:now+600,nonce:good.nonce),now:now,"Reject unbounded QR acceptance interval")
        reject(BroadcastPairing(kind:good.kind,version:1,server:good.server,token:good.token,acceptUntil:good.acceptUntil,nonce:"bad"),now:now,"Reject invalid nonce")
        expect((try? BroadcastPairing.decode(String(repeating:"x",count:2049),now:now)) == nil,"Bound QR input")
        // Render at the actual 240-point UI size on 2x/3x phone screens, then
        // decode the pixels with the same Vision QR API used by ReplayKit.
        // A forged fixture signature passing local shape checks is intentional:
        // backend signature validation, tested separately, is mandatory.
        guard let qr = good.qrImage() else { fatalError("QR generation failed") }
        for scale in [2,3] {
            let width=390*scale, height=844*scale
            let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:width,height:height))
            context.interpolationQuality = .none
            context.draw(qr,in:CGRect(x:75*scale,y:260*scale,width:240*scale,height:240*scale))
            let image=context.makeImage()!
            let request=VNDetectBarcodesRequest();request.symbologies=[.qr]
            try VNImageRequestHandler(cgImage:image).perform([request])
            let found=(request.results ?? []).compactMap { $0.payloadStringValue }.compactMap { try? BroadcastPairing.decode($0,now:now) }
            expect(found.contains { $0.nonce == good.nonce }, "Vision must decode actual rendered QR at \(scale)x")
        }
        print("PASS QR pixel/Vision round-trip at 2x and 3x, pinned endpoint, short expiry, token shape and input limits. No shared entitlements required. Physical ReplayKit capture not tested.")
    }
}
