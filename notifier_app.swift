import Cocoa
import UserNotifications

// Time to wait after the notification is added to the center before
// terminating the process. The completion handler fires when the request
// is enqueued, but the system may still need a moment to actually present
// the banner; exiting too quickly can drop the notification.
private let presentationDelay: DispatchTimeInterval = .milliseconds(500)

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: notifier TITLE MESSAGE\n".utf8))
    exit(2)
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let title: String
    let body: String
    init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = self.title
            content.body = self.body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + presentationDelay) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(title: args[1], body: args[2])
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
