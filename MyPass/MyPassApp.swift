import SwiftUI

@main
struct MyPassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .tint(Color.mp.ocean)
                .onOpenURL { url in
                    appState.handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await appState.didBecomeActive() }
            }
        }
    }
}

// MARK: - AppDelegate for APNs Push Notifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleNotification(userInfo: userInfo)
        }
        completionHandler(.newData)
    }
}
