import Foundation
import Testing
@testable import BoltunKit

@Suite struct FileTypeFilterTests {
    @Test func menuOrderAndTitlesMatchTheWebapp() {
        #expect(FileTypeFilter.allCases.map(\.rawValue) == ["all", "documents", "spreadsheets", "presentations", "code", "images", "audio", "video"])
        #expect(FileTypeFilter.allCases.map(\.title) == ["All file types", "Documents", "Spreadsheets", "Presentations", "Code", "Images", "Audio", "Videos"])
    }

    @Test func extensionGroupsMatchTheWebapp() {
        #expect(FileTypeFilter.all.extensions.isEmpty)
        #expect(FileTypeFilter.documents.extensions == ["doc", "pdf", "docx", "odt", "rtf", "txt"])
        #expect(FileTypeFilter.spreadsheets.extensions == ["xls", "xlsx", "ods"])
        #expect(FileTypeFilter.presentations.extensions == ["ppt", "pptx", "odp"])
        #expect(FileTypeFilter.code.extensions == ["py", "go", "java", "kt", "c", "cpp", "h", "html", "js", "ts", "cs", "vb", "php", "pl", "r", "rb", "sql", "swift", "json"])
        #expect(FileTypeFilter.images.extensions == ["png", "jpg", "jpeg", "bmp", "tiff", "svg", "xcf"])
        #expect(FileTypeFilter.audio.extensions == ["ogg", "mp3", "wav", "flac"])
        #expect(FileTypeFilter.video.extensions == ["ogm", "mp4", "avi", "webm", "mov", "mkv", "mpeg", "mpg"])
    }
}

@Suite struct FileKindTests {
    @Test(arguments: [
        ("txt", FileKind.text), ("RTF", .text), ("vtt", .text),
        ("png", .image), ("JPG", .image), ("webp", .image), ("gif", .image),
        ("mp3", .audio), ("m4a", .audio), ("mp4", .video), ("mov", .video),
        ("xlsx", .spreadsheet), ("csv", .spreadsheet), ("xls", .other),
        ("swift", .code), ("py", .code), ("json", .code), ("yaml", .code), ("ts", .other),
        ("doc", .word), ("docx", .word), ("ppt", .presentation), ("pptx", .presentation),
        ("pdf", .pdf), ("patch", .patch), ("svg", .svg), ("zip", .other), ("", .other),
    ])
    func classifiesLikeTheWebapp(ext: String, kind: FileKind) {
        #expect(FileKind.of(extension: ext) == kind)
    }

    @Test func fileInfoFallsBackToMimeTypeWithoutExtension() {
        #expect(FileInfo(id: "f", name: "a.pdf", extension: "pdf").kind == .pdf)
        #expect(FileInfo(id: "f", name: "shot", mimeType: "image/png").kind == .image)
        #expect(FileInfo(id: "f", name: "blob", mimeType: "application/octet-stream").kind == .other)
    }
}

@Suite struct ChannelFileQueryTests {
    @Test func scopesTermsToTheChannel() {
        let query = ChannelFileQuery(channelId: "c1")
        #expect(query.terms == "channel:c1")
        #expect(!query.isSearch)
    }

    @Test func appendsSearchTextAndExtensions() {
        let query = ChannelFileQuery(channelId: "c1", text: "  quarterly report ", filter: .spreadsheets)
        #expect(query.trimmedText == "quarterly report")
        #expect(query.isSearch)
        #expect(query.terms == "quarterly report channel:c1 ext:xls ext:xlsx ext:ods")
        #expect(ChannelFileQuery(channelId: "c1", text: " ", filter: .audio).terms == "channel:c1 ext:ogg ext:mp3 ext:wav ext:flac")
    }

    @Test func encodesTheWebappRequestBody() throws {
        let request = FileSearchRequest(terms: "channel:c1", timeZoneOffset: 7200, page: 2, perPage: 20)
        let object = try #require(JSONSerialization.jsonObject(with: MattermostJSON.encoder.encode(request)) as? [String: Any])
        #expect(object["terms"] as? String == "channel:c1")
        #expect(object["is_or_search"] as? Bool == false)
        #expect(object["include_deleted_channels"] as? Bool == true)
        #expect(object["time_zone_offset"] as? Int == 7200)
        #expect(object["page"] as? Int == 2)
        #expect(object["per_page"] as? Int == 20)
        #expect(object.count == 6)
    }

    @Test func decodesResultsInServerOrder() throws {
        let json = #"""
        {"order":["f2","missing","f1"],"file_infos":{
          "f1":{"id":"f1","post_id":"p1","user_id":"u1","channel_id":"c1","create_at":100,"name":"a.txt","extension":"txt","size":12,"mime_type":"text/plain"},
          "f2":{"id":"f2","post_id":"p2","user_id":"u2","channel_id":"c1","create_at":"200","name":"b.png","extension":"png","size":2048,"has_preview_image":true}
        },"next_file_info_id":"","prev_file_info_id":"","first_inaccessible_file_time":0}
        """#
        let results = try MattermostJSON.decoder.decode(FileSearchResults.self, from: Data(json.utf8))
        #expect(results.orderedFiles.map(\.id) == ["f2", "f1"])
        let first = results.orderedFiles[0]
        #expect(first.userId == "u2")
        #expect(first.channelId == "c1")
        #expect(first.createAt == 200)
        #expect(first.hasPreviewImage)
        let empty = try MattermostJSON.decoder.decode(FileSearchResults.self, from: Data(#"{"order":null,"file_infos":null}"#.utf8))
        #expect(empty.orderedFiles.isEmpty)
    }

    @Test func fileInfoRoundTripsNewFields() throws {
        let file = FileInfo(id: "f", postId: "p", name: "n.txt", userId: "u", channelId: "c", createAt: 42)
        let decoded = try MattermostJSON.decoder.decode(FileInfo.self, from: MattermostJSON.encoder.encode(file))
        #expect(decoded == file)
        #expect(FileInfo(id: "f", name: "n").userId.isEmpty)
    }

    @Test func clientConfigFileAttachmentsFlag() {
        #expect(ClientConfig(values: [:]).enableFileAttachments)
        #expect(ClientConfig(values: ["EnableFileAttachments": "true"]).enableFileAttachments)
        #expect(!ClientConfig(values: ["EnableFileAttachments": "false"]).enableFileAttachments)
    }

    @Test func fileSearchDisabledErrorIsRecognised() {
        #expect(APIError.server(status: 501, body: nil).isFileSearchDisabled)
        #expect(APIError.server(status: 400, body: ServerErrorBody(id: APIError.fileSearchDisabledId, message: "off")).isFileSearchDisabled)
        #expect(!APIError.server(status: 500, body: nil).isFileSearchDisabled)
        #expect(!APIError.unauthorized(nil).isFileSearchDisabled)
    }
}

@Suite struct FileSearchEndpointTests {
    let transport = FakeTransport()
    var client: APIClient { APIClient(baseURL: URL(string: "https://chat.example.com")!, token: "tok", transport: transport) }

    @Test func postsToTeamOrTeamlessRoute() async throws {
        transport.on("POST", "teams/t1/files/search", json: #"{"order":["f"],"file_infos":{"f":{"id":"f","name":"a.txt"}}}"#)
        transport.on("POST", "files/search", json: #"{"order":[],"file_infos":{}}"#)
        let request = FileSearchRequest(terms: "channel:c", timeZoneOffset: 0, page: 0, perPage: 20)
        #expect(try await client.searchFiles(teamId: "t1", request).order == ["f"])
        #expect(try await client.searchFiles(teamId: nil, request).order.isEmpty)
        #expect(try await client.searchFiles(teamId: "", request).order.isEmpty)
        #expect(transport.count("POST", "teams/t1/files/search") == 1)
        #expect(transport.count("POST", "files/search") == 2)
        #expect(transport.last("POST", "teams/t1/files/search")?.jsonObject["terms"] as? String == "channel:c")
    }
}

@MainActor
@Suite struct ServerSessionChannelFilesTests {
    static let page = #"""
    {"order":["f2","f1"],"file_infos":{
      "f1":{"id":"f1","post_id":"p1","user_id":"u3","channel_id":"c-town","create_at":100,"name":"a.txt","extension":"txt"},
      "f2":{"id":"f2","post_id":"p2","user_id":"u2","channel_id":"c-town","create_at":200,"name":"b.pdf","extension":"pdf"}
    }}
    """#

    @Test func searchesTheCurrentTeamAndLoadsSenders() async throws {
        let server = MockServer()
        server.transport.on("POST", "teams/t1/files/search", json: Self.page)
        let session = await server.startedSession()
        let files = await session.searchChannelFiles(ChannelFileQuery(channelId: "c-town", text: "b", filter: .documents), page: 1)
        #expect(files?.map(\.id) == ["f2", "f1"])
        #expect(session.users["u3"]?.username == "carol")
        let body = try #require(server.transport.last("POST", "teams/t1/files/search")).jsonObject
        #expect(body["terms"] as? String == "b channel:c-town ext:doc ext:pdf ext:docx ext:odt ext:rtf ext:txt")
        #expect(body["page"] as? Int == 1)
        #expect(body["per_page"] as? Int == ServerSession.channelFilesPageSize)
        #expect(body["include_deleted_channels"] as? Bool == true)
        #expect(body["time_zone_offset"] as? Int == TimeZone.current.secondsFromGMT(for: session.now()))
        session.stop()
    }

    @Test func usesTeamlessRouteWithoutCurrentTeam() async {
        let server = MockServer()
        server.transport.on("POST", "files/search", json: Self.page)
        let session = await server.startedSession(team: nil)
        session.currentTeamId = nil
        #expect(await session.searchChannelFiles(ChannelFileQuery(channelId: "dm"), page: 0)?.count == 2)
        #expect(server.transport.count("POST", "files/search") == 1)
        session.stop()
    }

    @Test func disabledFileSearchShowsAsEmptyWithoutError() async {
        let server = MockServer()
        server.transport.on("POST", "teams/t1/files/search", .error(501, id: APIError.fileSearchDisabledId, message: "Searching files has been disabled on this server."))
        let session = await server.startedSession()
        #expect(await session.searchChannelFiles(ChannelFileQuery(channelId: "c-town"), page: 0) == [])
        #expect(session.lastError == nil)
        session.stop()
    }

    @Test func otherFailuresAreReported() async {
        let server = MockServer()
        server.transport.on("POST", "teams/t1/files/search", .error(500, message: "search down"))
        let session = await server.startedSession()
        #expect(await session.searchChannelFiles(ChannelFileQuery(channelId: "c-town"), page: 0) == nil)
        #expect(session.lastError == "search down")
        session.stop()
    }
}
