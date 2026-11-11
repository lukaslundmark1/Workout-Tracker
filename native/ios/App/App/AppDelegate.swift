import UIKit
import Capacitor
import WebKit
import ObjectiveC

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// The app's screen: Capacitor's web view (set as the custom class in Main.storyboard), with one change.
/// WebKit draws web content inside apps at about 60 frames per second even on 120 Hz (ProMotion) iPhones. That cap is a WebKit
/// setting ("PreferPageRenderingUpdatesNear60FPSEnabled") that only Apple's private API can switch off, which is fine for this
/// app (it's installed from Xcode, not the App Store). It's switched off before the web view is created. If a future iOS
/// doesn't have the setting, nothing happens and the app simply stays at 60 fps.
class AppViewController: CAPBridgeViewController {
    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let configuration = super.webViewConfiguration(for: instanceConfiguration)
        AppViewController.liftFrameRateCap(configuration.preferences)
        return configuration
    }

    private static func liftFrameRateCap(_ preferences: WKPreferences) {
        let featuresSelector = NSSelectorFromString("_features")
        let setEnabledSelector = NSSelectorFromString("_setEnabled:forFeature:")
        guard let meta = object_getClass(WKPreferences.self),
              class_respondsToSelector(meta, featuresSelector),
              preferences.responds(to: setEnabledSelector),
              let featuresImp = class_getMethodImplementation(meta, featuresSelector) else {
            NSLog("Training: the 60 fps setting isn't available on this iOS version")
            return
        }
        typealias Features = @convention(c) (AnyClass, Selector) -> NSArray?
        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool, AnyObject) -> Void
        let features = unsafeBitCast(featuresImp, to: Features.self)
        guard let list = features(WKPreferences.self, featuresSelector) as? [NSObject] else { return }
        for feature in list where feature.responds(to: NSSelectorFromString("key")) {
            guard (feature.value(forKey: "key") as? String) == "PreferPageRenderingUpdatesNear60FPSEnabled" else { continue }
            let setEnabled = unsafeBitCast(preferences.method(for: setEnabledSelector), to: SetEnabled.self)
            setEnabled(preferences, setEnabledSelector, false, feature)
            NSLog("Training: drawing at the screen's full refresh rate (up to 120 Hz)")
            return
        }
        NSLog("Training: the 60 fps setting wasn't found on this iOS version")
    }
}
