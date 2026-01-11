import UIKit

@main
class TestAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create window
        window = UIWindow(frame: UIScreen.main.bounds)

        // Set root view controller
        let viewController = TestDualCaptureViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }
}
