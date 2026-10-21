import AppKit

let args = CommandLine.arguments
let environment = ProcessInfo.processInfo.environment

// OpenSSH runs SSH_ASKPASS programs with a single prompt argument; the hook passes repository and remote.
let askpassPrompt: String? = args.count == 2 ? args[1] : nil
// SSH_ASKPASS_PROMPT is unset for input, "confirm" for yes/no questions, "none" for touch notifications.
let askpassKind = environment["SSH_ASKPASS_PROMPT"] ?? ""

func label(_ content: String, size: CGFloat, strong: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: content)
    field.font = strong ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    field.alignment = .center
    field.lineBreakMode = .byTruncatingMiddle
    field.maximumNumberOfLines = 2
    return field
}

final class Delegate: NSObject, NSApplicationDelegate {
    let subtitle: String
    let details: [NSTextField]
    var panel: NSPanel?

    init(subtitle: String, details: [NSTextField]) {
        self.subtitle = subtitle
        self.details = details
    }

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

        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Touch your YubiKey")
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 45, weight: .medium)
        symbol.contentTintColor = .systemGreen
        stack.addArrangedSubview(symbol)
        stack.addArrangedSubview(label("Touch your YubiKey", size: 22, strong: true))
        stack.addArrangedSubview(label(subtitle, size: 12))
        details.forEach(stack.addArrangedSubview)
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

// Askpass input: print the answer to stdout for OpenSSH. Cancel or empty input exits non-zero,
// so no PIN attempt is sent to the YubiKey and its retry counter is untouched.
func askForInput(_ prompt: String) -> Never {
    let secret = prompt.range(of: "PIN|passphrase|password", options: [.regularExpression, .caseInsensitive]) != nil
    let frame = NSRect(x: 0, y: 0, width: 280, height: 24)
    let field = secret ? NSSecureTextField(frame: frame) : NSTextField(frame: frame)
    let alert = NSAlert()
    alert.messageText = "YubiKey Git Approval"
    alert.informativeText = prompt
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    alert.accessoryView = field
    alert.layout()
    alert.window.level = .floating
    alert.window.initialFirstResponder = field
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { exit(1) }
    FileHandle.standardOutput.write(Data((field.stringValue + "\n").utf8))
    exit(0)
}

func askForConfirmation(_ prompt: String) -> Never {
    let alert = NSAlert()
    alert.messageText = "YubiKey Git Approval"
    alert.informativeText = prompt
    alert.addButton(withTitle: "Yes")
    alert.addButton(withTitle: "No")
    alert.window.level = .floating
    NSApp.activate(ignoringOtherApps: true)
    exit(alert.runModal() == .alertFirstButtonReturn ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate: Delegate
switch (askpassPrompt, askpassKind) {
case let (prompt?, "none"):
    delegate = Delegate(subtitle: "Physical presence required to authenticate Git push", details: [label(prompt, size: 12)])
case let (prompt?, "confirm"):
    askForConfirmation(prompt)
case let (prompt?, _):
    askForInput(prompt)
default:
    let repository = args.count > 1 ? args[1] : "Unknown repository"
    let remote = args.count > 2 ? args[2] : "Unknown remote"
    delegate = Delegate(subtitle: "Physical presence required to authorize Git push", details: [
        label("Repository: \(repository)", size: 13, strong: true),
        label("Remote: \(remote)", size: 12)
    ])
}
app.delegate = delegate
app.run()
