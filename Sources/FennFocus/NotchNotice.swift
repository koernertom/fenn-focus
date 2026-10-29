import AppKit
import SwiftUI

/// One thing the notch says for a moment – a task done, the focus block over, a meeting in five minutes.
struct IslandNotice: Identifiable, Equatable {
    let id = UUID()
    /// SF Symbol, used when there's no clay picture.
    var symbol: String
    /// Clay picture from the asset catalogue, preferred over the symbol.
    var art: String? = nil
    var title: String
    var detail: String? = nil
    /// Short and on the right: "16:45", "5 min".
    var trailing: String? = nil
    /// Clicking the notice opens this module.
    var module: IslandModule? = nil
    var duration: Double = 4.2
}

/// Dynamic-Island-style notices on the Mac: the black notch grows sideways and down, says its line and shrinks back
/// into the notch. Own see-through window above the island, so the island's layout never moves. Without a notch it
/// grows from a small black pill under the menu bar. Hovering keeps it open, a click opens the matching module.
@MainActor
final class NotchNotices: ObservableObject {
    static let shared = NotchNotices()
    static let enabledKey = "fenn.mac.notices"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    @Published private(set) var current: IslandNotice?
    @Published fileprivate(set) var open = false
    fileprivate var hovering = false

    /// Where it grows from – set by the island controller: the screen, and the notch's width and height (0 without a notch).
    var anchor: () -> (screen: NSScreen, notchWidth: CGFloat, barHeight: CGFloat)? = { nil }
    /// Only while the island is closed – an open island shows everything anyway.
    var canShow: () -> Bool = { true }
    var onOpen: (IslandModule?) -> Void = { _ in }

    private var panel: NSPanel?
    private var run: Task<Void, Never>?
    private var queue: [IslandNotice] = []

    static let openWidth: CGFloat = 400
    static let rowHeight: CGFloat = 62

    func post(_ notice: IslandNotice) {
        guard Self.isEnabled, canShow() else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: [notice.title, notice.detail].compactMap { $0 }.joined(separator: ", "),
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        if current != nil {
            // Already out: the newest line takes over, at most one waits behind it.
            queue = [notice]
            return
        }
        show(notice)
    }

    private func show(_ notice: IslandNotice) {
        guard let anchor = anchor() else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let notch = anchor.notchWidth > 0
        let closed = notch ? CGSize(width: anchor.notchWidth, height: anchor.barHeight) : CGSize(width: 150, height: 30)
        let size = CGSize(width: Self.openWidth + 40, height: (notch ? anchor.barHeight : 0) + Self.rowHeight + 24)
        let screen = anchor.screen
        let top = notch ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        let centerX = notch && screen.auxiliaryTopLeftArea != nil
            ? screen.frame.minX + (screen.auxiliaryTopLeftArea?.width ?? 0) + anchor.notchWidth / 2
            : screen.frame.midX
        current = notice
        open = false
        let host = NSHostingView(rootView: NotchNoticeView(store: self, closed: closed, barHeight: notch ? anchor.barHeight : 0, notch: notch))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(NSRect(x: (centerX - size.width / 2).rounded(), y: top - size.height, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        run?.cancel()
        run = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            self?.open = true
            await self?.hold(notice.duration)
        }
    }

    /// Stays out for `seconds` (longer while the mouse rests on it), then shrinks back – or hands over to the next one.
    private func hold(_ seconds: Double) async {
        var left = seconds
        while left > 0 || hovering {
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
            if !hovering { left -= 0.2 }
            if let next = queue.first, !hovering {
                queue.removeAll()
                withAnimation(.easeInOut(duration: 0.2)) { current = next }
                left = next.duration
            }
        }
        close()
    }

    fileprivate func tap() {
        let module = current?.module
        close()
        onOpen(module)
    }

    private func close() {
        open = false
        run?.cancel()
        run = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            // Dropped, not just hidden – a hidden window would keep its animations running.
            self.panel?.contentView = nil
            self.current = nil
            self.hovering = false
            if let next = self.queue.first {
                self.queue.removeAll()
                self.show(next)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the island (status bar level), so it can grow out of the notch over the pill.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

/// The black shape that grows out of the notch, and the line inside it.
private struct NotchNoticeView: View {
    @ObservedObject var store: NotchNotices
    let closed: CGSize
    let barHeight: CGFloat
    let notch: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = store.open
        let width = open ? NotchNotices.openWidth : closed.width
        let height = open ? barHeight + NotchNotices.rowHeight : closed.height
        let radius: CGFloat = open ? 24 : (notch ? 10 : closed.height / 2)
        ZStack(alignment: .bottom) {
            shape(radius).fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.28 : 0), radius: 14, y: 6)
            if open, let notice = store.current {
                row(notice)
                    .id(notice.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: width, height: height)
        .opacity(notch || open ? 1 : 0)
        .contentShape(shape(radius))
        .onHover { store.hovering = $0 }
        .onTapGesture { store.tap() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74), value: open)
        .animation(.easeInOut(duration: 0.2), value: store.current)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Flat on top where it meets the screen edge (with a notch), round below.
    private func shape(_ radius: CGFloat) -> UnevenRoundedRectangle {
        let top = notch ? 0 : radius
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: radius,
                                      bottomTrailingRadius: radius, topTrailingRadius: top, style: .continuous)
    }

    private func row(_ notice: IslandNotice) -> some View {
        HStack(spacing: 12) {
            Group {
                if let art = notice.art {
                    Image(art).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: notice.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Fenn.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.fenn(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail = notice.detail {
                    Text(detail)
                        .font(.fenn(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = notice.trailing {
                Text(trailing)
                    .font(.fenn(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Fenn.accent)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: NotchNotices.rowHeight)
    }
}

#if DEBUG
extension NotchNotices {
    /// QA: the notice drawn open, without a window (-FennQANotice <file.png>).
    static func qaStrip(barHeight: CGFloat) -> some View {
        let store = NotchNotices()
        store.current = IslandNotice(symbol: "checkmark", art: "Page-tasks", title: "Angebotsentwurf schicken", detail: "Aufgabe erledigt", trailing: "5 min")
        store.open = true
        return NotchNoticeView(store: store, closed: CGSize(width: 190, height: barHeight), barHeight: barHeight, notch: true)
            .frame(width: openWidth + 40, height: barHeight + rowHeight + 24)
            .background(Color(white: 0.85))
    }
}
#endif
