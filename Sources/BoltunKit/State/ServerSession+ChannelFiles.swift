import Foundation

extension APIError {
    public static let fileSearchDisabledId = "store.sql_file_info.search.disabled"

    public var isFileSearchDisabled: Bool {
        guard case .server(let status, let body) = self else { return false }
        return status == 501 || body?.id == Self.fileSearchDisabledId
    }
}

extension ServerSession {
    public static let channelFilesPageSize = 20

    public func channelFilesRequest(_ query: ChannelFileQuery, page: Int) -> FileSearchRequest {
        FileSearchRequest(
            terms: query.terms,
            timeZoneOffset: TimeZone.current.secondsFromGMT(for: now()),
            page: page,
            perPage: Self.channelFilesPageSize
        )
    }

    public func searchChannelFiles(_ query: ChannelFileQuery, page: Int) async -> [FileInfo]? {
        do {
            let results = try await client.searchFiles(teamId: currentTeamId, channelFilesRequest(query, page: page))
            return results.orderedFiles
        } catch {
            if APIError.wrap(error).isFileSearchDisabled { return [] }
            report(error)
            return nil
        }
    }
}
