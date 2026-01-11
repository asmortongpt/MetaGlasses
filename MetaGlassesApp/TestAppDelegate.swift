import UIKit

/// Test version of AppDelegate that uses mock implementations
/// Run this in the iOS Simulator for testing without physical glasses
@main
class TestAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)

        // Create test view controller with mock camera manager
        let testViewController = TestDualCaptureViewController()
        let navigationController = UINavigationController(rootViewController: testViewController)
        navigationController.navigationBar.prefersLargeTitles = true

        // Add test mode indicator
        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .systemOrange.withAlphaComponent(0.3)
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance

        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        print("🧪 MetaGlasses TEST MODE launched")
        print("ℹ️  Using mock camera implementation for simulator testing")

        return true
    }
}
