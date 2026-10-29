import AppKit

final class ActionRelay: NSObject {
    private let handler: (AnyObject) -> Void

    init(handler: @escaping (AnyObject) -> Void) {
        self.handler = handler
    }

    @objc func invoke(_ sender: AnyObject) {
        handler(sender)
    }
}

final class ActionButton: NSButton {
    private var relay: ActionRelay!

    init(title: String, handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        relay = ActionRelay { _ in handler() }
        target = relay
        action = #selector(ActionRelay.invoke(_:))
    }

    required init?(coder: NSCoder) {
        nil
    }
}
