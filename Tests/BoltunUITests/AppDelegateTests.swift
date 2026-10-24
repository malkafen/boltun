import AppKit
import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
struct AppDelegateTests {
    @Test func drivesEnvironmentThroughLifecycle() async {
        _ = NSApplication.shared
        let harness = await Harness.connected()
        let delegate = AppDelegate()
        let environment = harness.environment()
        delegate.environment = environment
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)
        delegate.applicationWillFinishLaunching(notification)
        #expect(NSApp.appearance?.name == .darkAqua)
        delegate.applicationDidFinishLaunching(notification)
        #expect(environment.mainWindow?.isVisible == true)
        environment.mainWindow?.orderOut(nil)
        #expect(!delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        #expect(environment.mainWindow?.isVisible == true)
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))

        delegate.application(NSApp, open: [URL(string: "mattermost://chat.example.com:8065/team-two/channels/random")!])
        #expect(await eventually { harness.model.selectedSession?.currentChannelId == "c4" })

        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "mattermost://chat.example.com:8065/team-one/channels/off-topic"), forKeyword: keyDirectObject)
        delegate.handleURLEvent(event, replyEvent: NSAppleEventDescriptor.null())
        #expect(await eventually { harness.model.selectedSession?.currentChannelId == "c2" })
        delegate.handleURLEvent(NSAppleEventDescriptor.null(), replyEvent: NSAppleEventDescriptor.null())

        delegate.applicationWillTerminate(notification)
        #expect(harness.model.selectedSession?.connection == .idle)
        environment.mainWindow?.orderOut(nil)
    }
}
