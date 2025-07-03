import Flutter
import UIKit
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ✅ Firebase 초기화
    FirebaseApp.configure()

    // ✅ Flutter 플러그인 등록
    GeneratedPluginRegistrant.register(with: self)

    // ✅ 알림 등록 (iOS 10 이상에서 사용자에게 알림 권한 요청)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
