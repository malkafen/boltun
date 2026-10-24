import AppKit
import BoltunKit
import Foundation
import Observation
import ServiceManagement

@MainActor
public protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public final class SystemLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
@Observable
public final class GeneralSettingsViewModel {
    public let model: AppModel
    let loginItem: LoginItemControlling
    public private(set) var loginItemError: String?

    public init(model: AppModel, loginItem: LoginItemControlling) {
        self.model = model
        self.loginItem = loginItem
    }

    public var launchAtLogin: Bool {
        get { model.settings.launchAtLogin }
        set {
            do {
                try loginItem.setEnabled(newValue)
                loginItemError = nil
            } catch {
                loginItemError = "Could not update the login item: \(error.localizedDescription)"
            }
            model.settings.launchAtLogin = loginItem.isEnabled
        }
    }

    public static var defaultDownloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Downloads")
    }

    public var downloadURL: URL {
        model.settings.downloadLocation.map { URL(fileURLWithPath: $0) } ?? Self.defaultDownloadsURL
    }

    public var downloadLocationDisplay: String {
        (downloadURL.path as NSString).abbreviatingWithTildeInPath
    }

    public func setDownloadLocation(_ url: URL?) {
        model.settings.downloadLocation = url?.path
    }

    public func chooseDownloadLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloadURL
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { setDownloadLocation(url) }
    }
}
