import AppKit
import SwiftUI
import WebKit

/// SwiftUI's macOS 26 `WebView` does not expose a reliable first-responder or
/// unmodified-key-command API. These narrow bridges keep keyboard and native
/// window-toolbar behavior scoped to one reader window.
struct ReaderKeyboardShortcutMonitor: NSViewRepresentable {
    let onCommand: (ReaderKeyCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommand: onCommand)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ReaderKeyboardMarkerView()
        context.coordinator.hostView = view
        context.coordinator.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onCommand = onCommand
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onCommand: (ReaderKeyCommand) -> Bool
        private var monitor: Any?

        init(onCommand: @escaping (ReaderKeyCommand) -> Bool) {
            self.onCommand = onCommand
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let readerWindow = hostView?.window,
                      event.window === readerWindow,
                      let command = ReaderKeyCommand(event: event) else {
                    return event
                }
                if command != .findInBook, Self.isTextEditing(in: readerWindow) {
                    return event
                }
                return onCommand(command) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private static func isTextEditing(in window: NSWindow) -> Bool {
            window.firstResponder is NSTextView || window.firstResponder is NSTextField
        }
    }
}

/// SwiftUI has no hover region for the empty portion of a native window toolbar.
/// This marker observes pointer movement in its own window and reports whether
/// the pointer is above the unobscured content layout rectangle.
struct ReaderWindowToolbarHoverMonitor: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHoverChange: onHoverChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ReaderToolbarHoverMarkerView()
        view.onWindowChange = { [weak coordinator = context.coordinator] in
            coordinator?.windowDidChange()
        }
        context.coordinator.hostView = view
        context.coordinator.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onHoverChange = onHoverChange
        context.coordinator.installMonitorIfNeeded()
        context.coordinator.windowDidChange()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onHoverChange: (Bool) -> Void
        private weak var observedWindow: NSWindow?
        private var originalAcceptsMouseMovedEvents = false
        private var isPointerOverToolbar = false
        private var monitor: Any?

        init(onHoverChange: @escaping (Bool) -> Void) {
            self.onHoverChange = onHoverChange
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func windowDidChange() {
            guard observedWindow !== hostView?.window else { return }
            restoreWindowSetting()
            observedWindow = hostView?.window
            if let observedWindow {
                originalAcceptsMouseMovedEvents = observedWindow.acceptsMouseMovedEvents
                observedWindow.acceptsMouseMovedEvents = true
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            restoreWindowSetting()
        }

        private func handle(_ event: NSEvent) {
            guard let observedWindow else {
                updateHover(false)
                return
            }
            let isOverToolbar = event.window === observedWindow
                && event.locationInWindow.y >= observedWindow.contentLayoutRect.maxY
            updateHover(isOverToolbar)
        }

        private func updateHover(_ isOverToolbar: Bool) {
            guard isOverToolbar != isPointerOverToolbar else { return }
            isPointerOverToolbar = isOverToolbar
            onHoverChange(isOverToolbar)
        }

        private func restoreWindowSetting() {
            observedWindow?.acceptsMouseMovedEvents = originalAcceptsMouseMovedEvents
            observedWindow = nil
            if isPointerOverToolbar {
                isPointerOverToolbar = false
                onHoverChange(false)
            }
        }
    }
}

struct ReaderFocusRequester: NSViewRepresentable {
    let area: ReaderFocusArea
    let isActive: Bool
    let requestID: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        ReaderKeyboardMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isActive, context.coordinator.lastRequestID != requestID else { return }
        context.coordinator.lastRequestID = requestID
        Task { @MainActor [weak nsView] in
            await Task.yield()
            guard let nsView else { return }
            Self.focus(area, from: nsView)
        }
    }

    @MainActor
    final class Coordinator {
        var lastRequestID: Int?
    }

    @MainActor
    private static func focus(_ area: ReaderFocusArea, from marker: NSView) {
        guard let window = marker.window else { return }
        var root = marker.superview
        while let candidate = root {
            let target: NSView?
            switch area {
            case .readerPanel:
                target = firstDescendant(of: WKWebView.self, in: candidate)
            case .sidebar:
                target = firstDescendant(of: NSTableView.self, in: candidate)
            }
            if let target {
                window.makeFirstResponder(target)
                return
            }
            root = candidate.superview
        }
    }

    private static func firstDescendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for child in root.subviews {
            if let match = firstDescendant(of: type, in: child) {
                return match
            }
        }
        return nil
    }
}

private final class ReaderKeyboardMarkerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class ReaderToolbarHoverMarkerView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

enum ReaderKeyCommand: Equatable {
    case findInBook
    case addBookmark
    case toggleSidebar
    case previousChapter
    case nextChapter
    case previousSidebarItem
    case nextSidebarItem

    init?(event: NSEvent) {
        let shortcutModifiers = event.modifierFlags.intersection(
            [.command, .control, .option, .shift]
        )
        if shortcutModifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            self = .findInBook
            return
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return nil }

        switch event.specialKey {
        case .leftArrow:
            self = .previousChapter
        case .rightArrow:
            self = .nextChapter
        case .upArrow:
            self = .previousSidebarItem
        case .downArrow:
            self = .nextSidebarItem
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": self = .addBookmark
            case "c": self = .toggleSidebar
            default: return nil
            }
        }
    }
}
