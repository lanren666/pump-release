import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else {
            return
        }

        // 获取 AppDelegate
        guard let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate else {
            return
        }

        // 如果 AppDelegate 已经有 window，使用它
        if let existingWindow = appDelegate.window {
            existingWindow.windowScene = windowScene
            self.window = existingWindow
        } else {
            // 创建新的 window
            let newWindow = UIWindow(windowScene: windowScene)

            // 创建 FlutterViewController
            let flutterEngine = FlutterEngine(name: "io.flutter", project: nil, allowHeadlessExecution: false)
            flutterEngine.run(withEntrypoint: nil)
            GeneratedPluginRegistrant.register(with: flutterEngine)

            let controller = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
            newWindow.rootViewController = controller
            newWindow.makeKeyAndVisible()

            self.window = newWindow
            appDelegate.window = newWindow
        }
    }
}

