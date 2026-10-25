import UIKit

/// The orientations the app allows right now. On the iPhone only the player turns; every other
/// screen stays portrait. The full-screen button turns the screen and holds it there until the
/// device is held the same way, so the turn doesn't snap straight back.
enum OrientationLock {
    private(set) static var mask = defaultMask
    private static var isPlayerOpen = false

    private static var defaultMask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return isPlayerOpen ? .allButUpsideDown : .portrait
    }

    /// Lets the iPhone turn while the player is open; closing it frees any lock and turns the
    /// screen back to portrait.
    static func playerExpanded(_ isExpanded: Bool) {
        let previous = mask
        isPlayerOpen = isExpanded
        mask = defaultMask
        if mask != previous { apply(mask) }
    }

    static func rotate(to orientation: UIInterfaceOrientationMask) {
        mask = orientation
        apply(orientation)
    }

    /// Frees the lock once the device itself is held the way the screen was turned.
    static func deviceRotated(to orientation: UIDeviceOrientation) {
        let matches = (mask == .landscape && orientation.isLandscape) || (mask == .portrait && orientation == .portrait)
        if matches { mask = defaultMask }
    }

    private static func apply(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        var controller = scene.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    func application(
        _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadEvents.completionHandler = completionHandler
        DownloadStore.shared.attach()
    }
}
