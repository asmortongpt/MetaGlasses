import UIKit

/// Production version of AppDelegate that uses real Meta glasses hardware
@main
class ProductionAppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)

        // Create ULTIMATE view controller with all features enabled
        let cameraManager = DualCameraManager()
        let imageEnhancer = AIImageEnhancer()
        let viewController = UltimateEnhancedViewController()
        viewController.cameraManager = cameraManager
        viewController.imageEnhancer = imageEnhancer
        viewController.enableVoiceCommands = true
        viewController.enableLiveStream = true

        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        print("🚀 MetaGlasses PRODUCTION MODE launched")
        print("📱 Using REAL Meta Ray-Ban glasses hardware")
        print("⚠️  Ensure glasses are paired via Meta View app")

        return true
    }
}
