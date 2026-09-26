import UIKit
import AVFoundation

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default)
            try s.setActive(true)
        } catch {
            print("audio session error: \(error)")
        }
        window = UIWindow(frame: UIScreen.main.bounds)
        let cloud = CloudViewController()
        window?.rootViewController = UINavigationController(rootViewController: cloud)
        window?.makeKeyAndVisible()
        return true
    }
}
