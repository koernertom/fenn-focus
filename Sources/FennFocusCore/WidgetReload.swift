import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Explicit WidgetKit reload – the host calls it after the widget snapshot changed.
public enum WidgetReload {
    /// Reloads all Fenn desktop widgets.
    public static func reloadAllTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
