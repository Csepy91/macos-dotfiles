import Foundation

/// Keeps Apple / Wi-Fi / Bluetooth popovers mutually exclusive and dismissible
/// from same-app bar clicks (global mouse monitors alone miss those events).
@MainActor
enum BarPopoverCoordinator {
    static func dismissAll() {
        AppleMenuController.shared.dismiss()
        WiFiMenuController.shared.dismiss()
        BluetoothMenuController.shared.dismiss()
    }

    /// Call before opening any bar popover so sibling menus never stack.
    static func willPresent() {
        dismissAll()
    }
}
