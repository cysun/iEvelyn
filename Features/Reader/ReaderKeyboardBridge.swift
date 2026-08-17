import AppKit
import SwiftUI
import WebKit

/// SwiftUI's macOS 26 `WebView` does not expose a reliable first-responder or
/// unmodified-key-command API. These two narrow bridges keep keyboard handling
/// scoped to one reader window while leaving text entry and other windows alone.
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
                      !Self.isTextEditing(in: readerWindow),
                      let command = ReaderKeyCommand(event: event) else {
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

enum ReaderKeyCommand: Equatable {
    case addBookmark
    case toggleSidebar
    case previousChapter
    case nextChapter
    case previousSidebarItem
    case nextSidebarItem

    init?(event: NSEvent) {
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
