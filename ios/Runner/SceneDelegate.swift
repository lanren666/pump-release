import UIKit
import Flutter

/// iOS 13+ 场景代理。与 Info.plist 中 `UISceneStoryboardFile = Main` 配合：
/// 系统从 Main.storyboard 创建 `FlutterViewController` 与 window，此处仅同步到 `FlutterAppDelegate`。
@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard scene is UIWindowScene else { return }
        guard let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate else { return }

        // Storyboard 场景：UIKit 已填充 self.window（含 FlutterViewController）
        if let storyboardWindow = window {
            appDelegate.window = storyboardWindow
            return
        }

        // 回退：复用 AppDelegate 已有 window，绑定 windowScene
        if let windowScene = scene as? UIWindowScene,
           let existingWindow = appDelegate.window
        {
            existingWindow.windowScene = windowScene
            window = existingWindow
        }
    }
}
