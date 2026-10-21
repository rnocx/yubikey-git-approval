import AppKit

let args = CommandLine.arguments
let repository = args.count > 1 ? args[1] : "Unknown repository"
let remote = args.count > 2 ? args[2] : "Unknown remote"

final class Delegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 275), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "YubiKey Git Approval"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)
        ])

        func label(_ content: String, size: CGFloat, strong: Bool = false) -> NSTextField {
            let field = NSTextField(labelWithString: content)
            field.font = strong ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
            field.alignment = .center
            field.lineBreakMode = .byTruncatingMiddle
            field.maximumNumberOfLines = 2
            return field
        }
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Touch your YubiKey")
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 45, weight: .medium)
        symbol.contentTintColor = .systemGreen
        stack.addArrangedSubview(symbol)
        stack.addArrangedSubview(label("Touch your YubiKey", size: 22, strong: true))
        stack.addArrangedSubview(label("Physical presence required to authorize Git push", size: 12))
        stack.addArrangedSubview(label("Repository: \(repository)", size: 13, strong: true))
        stack.addArrangedSubview(label("Remote: \(remote)", size: 12))
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.startAnimation(nil)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label("Waiting for hardware authentication…", size: 12))
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
