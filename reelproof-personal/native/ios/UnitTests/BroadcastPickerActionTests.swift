import XCTest
import UIKit
@testable import ReelProof

final class BroadcastPickerActionTests: XCTestCase {
    final class Target: NSObject {
        var count = 0
        @objc func tapped() { count += 1 }
    }
    func testOpensOnlyAfterAttachmentAndOnlyOncePerPrepareRequest() {
        let verify = {
            let action = BroadcastPickerAction(), container = UIView(), target = Target(), button = UIButton(type: .system)
            button.addTarget(target, action: #selector(Target.tapped), for: .touchUpInside);container.addSubview(button)
            XCTAssertFalse(action.open(container, request: 1));XCTAssertEqual(target.count, 0)
            let window = UIWindow(frame: UIScreen.main.bounds), controller = UIViewController()
            window.rootViewController = controller;controller.view.addSubview(container);window.isHidden = false
            defer { window.isHidden = true }
            XCTAssertFalse(action.open(container, request: 0));XCTAssertEqual(target.count, 0)
            XCTAssertTrue(action.open(container, request: 1));XCTAssertEqual(target.count, 1)
            XCTAssertTrue(action.open(container, request: 1));XCTAssertEqual(target.count, 1, "SwiftUI updates must not reopen Apple's UI repeatedly")
            XCTAssertTrue(action.open(container, request: 2));XCTAssertEqual(target.count, 2, "An explicit retry can reopen the picker")
            let unsupported = UIView();controller.view.addSubview(unsupported)
            XCTAssertFalse(action.open(unsupported, request: 3), "Unsupported hierarchy must preserve the visible manual fallback")
            XCTAssertEqual(target.count, 2)
        }
        if Thread.isMainThread { verify() } else { DispatchQueue.main.sync(execute: verify) }
    }
}
