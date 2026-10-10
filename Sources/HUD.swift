import AppKit

/// A small floating glass bar that shows the four apps. It never takes keyboard focus,
/// so whatever app you're in stays active until you pick something.
final class HUD {
    var onPick: ((Int) -> Void)?
    private(set) var isVisible = false

    private let panel: NSPanel
    private let stack = NSStackView()
    private var tiles: [TileView] = []

    init() {
        panel = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        let glass = NSGlassEffectView()
        glass.cornerRadius = 24
        glass.contentView = stack
        panel.contentView = glass
    }

    func show(apps: [URL?]) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = apps.enumerated().map { i, url in
            let tile = TileView(number: i + 1, appURL: url)
            tile.onClick = { [weak self] in self?.onPick?(i) }
            stack.addArrangedSubview(tile)
            return tile
        }

        let size = stack.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded())
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 1
        }
    }

    func highlight(_ index: Int) {
        guard tiles.indices.contains(index) else { return }
        tiles[index].isHighlighted = true
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.panel.orderOut(nil)
        })
    }
}

private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TileView: NSView {
    var onClick: (() -> Void)?
    var isHighlighted = false { didSet { needsDisplay = true } }

    init(number: Int, appURL: URL?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let appURL {
            icon.image = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            icon.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Empty")?
                .withSymbolConfiguration(.init(pointSize: 38, weight: .ultraLight))
            icon.contentTintColor = .tertiaryLabelColor
        }

        let name = NSTextField(labelWithString: appURL.map(appName) ?? "Empty")
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.textColor = appURL == nil ? .tertiaryLabelColor : .secondaryLabelColor
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail

        let badge = KeyBadge(number: number)

        for view in [icon, name, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 74),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            name.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            badge.centerXAnchor.constraint(equalTo: icon.trailingAnchor, constant: -3),
            badge.centerYAnchor.constraint(equalTo: icon.bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = 14
        layer?.backgroundColor = isHighlighted ? NSColor.labelColor.withAlphaComponent(0.14).cgColor : nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// The little keycap showing which number to press.
private final class KeyBadge: NSView {
    private let label: NSTextField

    init(number: Int) {
        label = NSTextField(labelWithString: "\(number)")
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 19),
            heightAnchor.constraint(equalToConstant: 19),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 6
        layer.borderWidth = 1.5
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(1).cgColor
            layer.borderColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7).cgColor
            label.textColor = .windowBackgroundColor
        }
    }
}
