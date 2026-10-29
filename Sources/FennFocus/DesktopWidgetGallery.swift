#if DEBUG
import SwiftUI
import WidgetKit
import FennFocusCore

/// QA only: every desktop widget at its macOS size, drawn into a PNG
/// (-FennQANoFocus YES -FennQASnapshot <file.png> -FennQAWidgetGallery light|dark).
struct DesktopWidgetGallery: View {
    let scheme: ColorScheme

    private let small = CGSize(width: 170, height: 170)
    private let medium = CGSize(width: 364, height: 170)
    private let large = CGSize(width: 364, height: 382)
    private var entry: FennDesktopEntry { FennDesktopEntry(date: Date(), snapshot: .placeholder) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                tile(small) { FennTodayDesktopView(entry: entry, familyOverride: .systemSmall) }
                tile(small, margins: false) { FennAgentDesktopView(entry: PebbleDesktopEntry(date: Date(), frame: 0, happy: true, dozing: false, german: true)) }
            }
            tile(medium) { FennTodayDesktopView(entry: entry, familyOverride: .systemMedium) }
            tile(large) { FennTodayDesktopView(entry: entry, familyOverride: .systemLarge) }
            HStack(spacing: 18) {
                tile(small) { FennHabitsDesktopView(entry: entry, familyOverride: .systemSmall) }
                tile(small) { FennFocusDesktopView(entry: entry, familyOverride: .systemSmall) }
            }
            tile(medium) { FennHabitsDesktopView(entry: entry, familyOverride: .systemMedium) }
            tile(large) { FennTasksDesktopView(entry: entry, familyOverride: .systemLarge) }
        }
        .padding(24)
        .background(scheme == .dark ? Color(red: 0.08, green: 0.10, blue: 0.12) : Color(red: 0.62, green: 0.70, blue: 0.74))
        .environment(\.colorScheme, scheme)
    }

    private func tile<Content: View>(_ size: CGSize, margins: Bool = true, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            DesktopClay.Background()
            content().padding(margins ? 16 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}
#endif
