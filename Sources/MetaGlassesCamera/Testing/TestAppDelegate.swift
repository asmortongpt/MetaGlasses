import UIKit

/// Test version of AppDelegate that uses mock implementations
/// Run this in the iOS Simulator for testing without physical glasses
/// Note: @main is removed - ProductionAppDelegate is the entry point for hardware
class TestAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)

        // Create enhanced test view controller with mock camera manager
        let testViewController = EnhancedTestDualCaptureViewController()

        window?.rootViewController = testViewController
        window?.makeKeyAndVisible()

        print("🧪 MetaGlasses TEST MODE launched")
        print("ℹ️  Using mock camera implementation for simulator testing")

        return true
    }
}
