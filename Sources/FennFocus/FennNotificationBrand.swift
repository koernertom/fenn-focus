import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Puts the current Fenn mark on a local notification. The system icon is the app icon;
/// the attachment is the same mark again, so Mitteilungen don't keep a stale picture.
enum FennNotificationBrand {
    static let iconName = "NotificationIcon"

    static let phaseIdentifier = "fenn.pomodoro.phase"

    static func authorizeIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func schedulePhase(after seconds: TimeInterval, title: String, body: String, url: String, identifier: String = phaseIdentifier) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard seconds > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url]
        apply(to: content)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
        center.add(request)
    }

    static func clearPhase() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [phaseIdentifier])
    }

    static func apply(to content: UNMutableNotificationContent) {
        guard let url = writeIcon() else { return }
        if let attachment = try? UNNotificationAttachment(identifier: "fenn-logo", url: url, options: nil) {
            content.attachments = [attachment]
        }
    }

    private static func writeIcon() -> URL? {
        let data: Data?
        #if os(iOS)
        data = UIImage(named: iconName)?.pngData()
        #else
        guard let image = NSImage(named: iconName) ?? NSApp.applicationIconImage else {
            data = nil
            return nil
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            data = rep.representation(using: .png, properties: [:])
        } else {
            data = nil
        }
        #endif
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fenn-notification-icon.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
