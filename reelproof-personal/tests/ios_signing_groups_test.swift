import Foundation

@main struct SigningGroupsTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
    static func xml(_ dictionary: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }
    static func words(_ values: [UInt32], bigEndian: Bool = false) -> Data {
        Data(values.flatMap { value in
            (bigEndian ? [24,16,8,0] : [0,8,16,24]).map { UInt8(truncatingIfNeeded: value >> $0) }
        })
    }
    static func executable(_ dictionary: [String: Any]) -> Data {
        let payload = xml(dictionary)
        let blob = words([0xfade7171, UInt32(8 + payload.count)], bigEndian: true) + payload
        let signature = words([0xfade0cc0, UInt32(20 + blob.count), 1, 5, 20], bigEndian: true) + blob
        return words([0xfeedfacf,0x0100000c,0,2,1,16,0,0,0x1d,16,48,UInt32(signature.count)]) + signature
    }
    static func main() throws {
        let original = "group.app.reelproof.test.shared"
        let renamed = original + ".TEAM123456"
        let other = "group.other.test"
        let fixture = executable([SigningGroups.entitlement:[renamed]])
        let keychain = "ABCDE12345.app.reelproof.test"
        expect(SigningGroups.signedEntitlements(executable(["keychain-access-groups":[keychain]]))?["keychain-access-groups"] as? [String] == [keychain], "Keychain groups read from actual signed metadata, independently of missing App Groups")
        expect(SigningGroups.signedGroups(fixture) == [renamed], "Read actual code-signature entitlement layout")
        expect(SigningGroups.signedGroups(executable([:])) == [], "Missing claim is not permission")
        for count in 0..<fixture.count {
            expect(SigningGroups.signedGroups(fixture.prefix(count)) == nil, "Reject truncated signature at \(count)")
        }
        expect(SigningGroups.signedGroups(Data(repeating: 0, count: 128)) == nil, "Reject non-Mach-O input")
        let profile = Data([0x30,0x80,0x00]) + xml(["Entitlements":[SigningGroups.entitlement:[renamed]]]) + Data([0,0])
        expect(SigningGroups.profileGroups(profile) == [renamed], "Read embedded provisioning XML without exposing other fields")
        expect(SigningGroups.profileGroups(Data("invalid".utf8)) == nil, "Unreadable profile is not a fabricated claim")
        expect(SigningGroups.profileGroups(xml(["Entitlements":[:]])) == [], "Profile without App Groups")
        func resolve(_ app: [String]?, _ ext: [String]?, _ appProfile: [String]? = nil, _ extProfile: [String]? = nil, access: Bool = true) -> SigningGroups.Resolution {
            SigningGroups.resolve(configured: original, appClaims: app, extensionClaims: ext, appProfile: appProfile, extensionProfile: extProfile) { _ in access }
        }
        expect(resolve([original],[original]).group == original, "Keep configured name when signed in both targets")
        expect(resolve([renamed],[renamed],[renamed],[renamed]).group == renamed, "Resolve same renamed group after signing")
        expect(resolve([original],[renamed]).group == nil, "Reject mismatched targets")
        expect(resolve([],[renamed]).group == nil, "Do not invent missing app rights")
        expect(resolve([renamed],[]).group == nil, "Do not invent missing extension rights")
        expect(resolve(nil,[renamed],[renamed],[renamed]).group == nil, "Profile alone cannot grant rights")
        expect(resolve([renamed],[renamed],[],[renamed]).group == nil, "Profile must allow the signed group")
        expect(resolve([renamed],[renamed],[renamed],[other]).group == nil, "Both profiles must allow the same group")
        expect(resolve([renamed],[renamed],access:false).group == nil, "Runtime container denial must stop setup")
        expect(resolve([other,original],[original,other]).group == original, "Prefer configured common group")
        expect(resolve([other,renamed],[renamed,other]).group == resolve([renamed,other],[other,renamed]).group, "Host and extension resolve deterministically")
        if CommandLine.arguments.count > 1 {
            let app = URL(fileURLWithPath: CommandLine.arguments[1])
            var read: [[String]] = []
            for target in [app, app.appendingPathComponent("PlugIns/BroadcastExtension.appex")] {
                let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: target.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
                let executable = target.appendingPathComponent(info["CFBundleExecutable"] as! String)
                guard let groups = SigningGroups.signedGroups(try Data(contentsOf: executable)) else { fatalError("Cannot parse compiled target signing metadata") }
                expect(groups == [info["ReelProofAppGroup"] as! String], "Read signed App Group in real compiled target")
                expect((SigningGroups.signedEntitlements(try! Data(contentsOf: executable))?["keychain-access-groups"] as? [String])?.count == 1, "Compiled targets retain keychain sharing metadata")
                read.append(groups)
            }
            expect(read[0] == read[1], "Real app and extension contain identical signed group claims")
        }
        print("PASS signing group resolution: renamed/missing/mismatched rights, profile bounds, runtime denial, deterministic host-extension selection, truncated data and compiled Mach-O metadata")
    }
}
