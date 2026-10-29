import Foundation

/// Framework bundle token so Shared JSON resources resolve when Core is linked
/// as a dynamic framework (Host + Widget Extension), not only as app `.main`.
public enum FennFocusCoreBundle {
    private final class Token {}
    public static let bundle: Bundle = Bundle(for: Token.self)
}
