import UIKit

/// Opens Apple's consent UI in response to the host's prepare action. It never
/// accepts the confirmation or starts recording itself. A visible system picker
/// remains available if an iOS version exposes a different view hierarchy.
final class BroadcastPickerAction {
    private var handledRequest = 0
    func open(_ view: UIView, request: Int) -> Bool {
        guard request > 0 else { return false }
        if handledRequest == request { return true }
        guard view.window != nil, let button = view.subviews.compactMap({ $0 as? UIButton }).first, button.isEnabled else { return false }
        handledRequest = request
        button.sendActions(for: .touchUpInside)
        return true
    }
}
