import Foundation
import Testing
@testable import BoltunKit

@Suite struct StorageTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "boltun-tests-\(UUID().uuidString)")
    }

    @Test func fileStoreRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAppStateStore(fileURL: directory.appending(path: "nested/state.json"))
        #expect(store.load() == AppState())
        var settings = AppSettings()
        settings.fontScale = 1.25
        settings.downloadLocation = "/tmp/downloads"
        settings.showMenuBarIcon = true
        let server = ServerConfig(name: "Work", url: URL(string: "https://chat.example.com")!, lastTeamId: "t1", lastChannelByTeam: ["t1": "c1"])
        settings.lastServerId = server.id
        let state = AppState(servers: [server], settings: settings)
        try store.save(state)
        #expect(store.load() == state)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"fontScale\" : 1.25"))
        try store.save(AppState())
        #expect(store.load().servers.isEmpty)
    }

    @Test func fileStoreRecoversFromCorruptFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "state.json")
        try Data("not json".utf8).write(to: url)
        #expect(FileAppStateStore(fileURL: url).load() == AppState())
        try Data("{}".utf8).write(to: url)
        #expect(FileAppStateStore(fileURL: url).load() == AppState())
    }

    @Test func fileStoreSaveFailsWhenDirectoryIsAFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appending(path: "blocker")
        try Data().write(to: blocker)
        let store = FileAppStateStore(fileURL: blocker.appending(path: "state.json"))
        #expect(throws: (any Error).self) { try store.save(AppState()) }
    }

    @Test func defaultURL() {
        let url = FileAppStateStore.defaultURL(appName: "BoltunTest")
        #expect(url.lastPathComponent == "state.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "BoltunTest")
        #expect(FileAppStateStore.defaultURL().path().contains("Boltun"))
    }

    @Test func memoryStore() throws {
        let store = MemoryAppStateStore()
        #expect(store.load() == AppState())
        let state = AppState(servers: [ServerConfig(name: "A", url: URL(string: "https://a.example.com")!)])
        try store.save(state)
        #expect(store.load() == state)
        #expect(MemoryAppStateStore(state).load() == state)
    }

    @Test func memoryCredentials() throws {
        let id = UUID()
        let other = UUID()
        let store = MemoryCredentialStore([other: "x"])
        #expect(store.token(for: id) == nil)
        try store.setToken("abc", for: id)
        try store.setToken("def", for: id)
        #expect(store.token(for: id) == "def")
        store.removeToken(for: id)
        store.removeToken(for: id)
        #expect(store.token(for: id) == nil)
        #expect(store.token(for: other) == "x")
    }

    @Test func keychainCredentials() {
        let store = KeychainCredentialStore(service: "io.github.malkafen.boltun.tests.\(UUID().uuidString)")
        let id = UUID()
        #expect(store.token(for: id) == nil)
        do {
            try store.setToken("first", for: id)
        } catch {
            return
        }
        defer { store.removeToken(for: id) }
        #expect(store.token(for: id) == "first")
        #expect((try? store.setToken("second", for: id)) != nil)
        #expect(store.token(for: id) == "second")
        store.removeToken(for: id)
        #expect(store.token(for: id) == nil)
        #expect(KeychainCredentialStore().service == "io.github.malkafen.boltun.session")
    }

    @Test func credentialErrorEquality() {
        #expect(CredentialStoreError.keychain(-25300) == .keychain(-25300))
        #expect(CredentialStoreError.keychain(-25300) != .keychain(-25308))
    }
}

@Suite struct ServerConfigTests {
    @Test(arguments: [
        ("My Server", "MS"),
        ("chat.example.com", "CE"),
        ("solo", "S"),
        ("dev-ops_team", "DO"),
        ("--", "-"),
        ("", ""),
    ])
    func initials(name: String, expected: String) {
        #expect(ServerConfig(name: name, url: URL(string: "https://x.example.com")!).initials == expected)
    }

    @Test func decodesPartialServerConfig() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Work","url":"https://chat.example.com"}"#
        let config = try JSONDecoder().decode(ServerConfig.self, from: Data(json.utf8))
        #expect(config.id == id)
        #expect(config.lastTeamId == nil)
        #expect(config.lastChannelByTeam.isEmpty)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ServerConfig.self, from: Data(#"{"name":"Work"}"#.utf8))
        }
    }

    @Test func decodesPartialSettings() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showUnreadBadge":false,"fontScale":"big","launchAtLogin":true}"#.utf8))
        #expect(settings.showUnreadBadge == false)
        #expect(settings.launchAtLogin)
        #expect(settings.fontScale == 1.0)
        #expect(settings.notificationsEnabled)
        #expect(settings.lastServerId == nil)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == AppSettings())
    }

    @Test func decodesPartialAppState() throws {
        let state = try JSONDecoder().decode(AppState.self, from: Data(#"{"version":2,"servers":"oops"}"#.utf8))
        #expect(state.version == 2)
        #expect(state.servers.isEmpty)
        #expect(state.settings == AppSettings())
        let encoded = try JSONEncoder().encode(AppState())
        #expect(try JSONDecoder().decode(AppState.self, from: encoded) == AppState())
    }
}
