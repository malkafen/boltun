import BoltunKit
import Foundation
import Testing
@testable import BoltunUI

@MainActor
final class FileFetchRecorder {
    var calls: [(query: ChannelFileQuery, page: Int)] = []
    var pages: [Int: [FileInfo]] = [:]
    var failing: Set<Int> = []
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false

    func fetch(_ query: ChannelFileQuery, _ page: Int) async -> [FileInfo]? {
        calls.append((query, page))
        if holdNext {
            holdNext = false
            await withCheckedContinuation { gate = $0 }
        }
        if failing.contains(page) { return nil }
        return pages[page] ?? []
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    static func files(_ range: ClosedRange<Int>, prefix: String = "f") -> [FileInfo] {
        range.map { FileInfo(id: "\(prefix)\($0)", postId: "p\($0)", name: "file-\($0).txt", extension: "txt") }
    }
}

@MainActor
@Suite struct ChannelFilesModelTests {
    func model(pageSize: Int = 3) -> (ChannelFilesModel, FileFetchRecorder) {
        let recorder = FileFetchRecorder()
        return (ChannelFilesModel(pageSize: pageSize) { await recorder.fetch($0, $1) }, recorder)
    }

    @Test func pagesUntilAShortPage() async {
        let (model, recorder) = model()
        recorder.pages = [0: FileFetchRecorder.files(1...3), 1: FileFetchRecorder.files(4...6), 2: FileFetchRecorder.files(7...7)]
        await model.open(channelId: "c1")
        #expect(model.files.map(\.id) == ["f1", "f2", "f3"])
        #expect(!model.isAtEnd)
        #expect(model.nextPage == 1)
        await model.loadMoreIfNeeded(after: model.files[0])
        #expect(recorder.calls.count == 1)
        await model.loadMoreIfNeeded(after: model.files[2])
        #expect(model.files.count == 6)
        await model.loadMore()
        #expect(model.files.count == 7)
        #expect(model.isAtEnd)
        await model.loadMore()
        #expect(recorder.calls.map(\.page) == [0, 1, 2])
        #expect(recorder.calls.allSatisfy { $0.query.channelId == "c1" })
    }

    @Test func emptyOrRepeatedPagesEndPagination() async {
        let (model, recorder) = model()
        recorder.pages = [0: FileFetchRecorder.files(1...3), 1: FileFetchRecorder.files(1...3)]
        await model.open(channelId: "c1")
        await model.loadMore()
        #expect(model.files.count == 3)
        #expect(model.isAtEnd)
        recorder.pages = [0: FileFetchRecorder.files(1...3)]
        await model.reload()
        await model.loadMore()
        #expect(model.isAtEnd)
        #expect(model.nextPage == 2)
    }

    @Test func failuresStopPaging() async {
        let (model, recorder) = model()
        recorder.failing = [0]
        await model.open(channelId: "c1")
        #expect(model.files.isEmpty)
        #expect(model.isAtEnd)
        #expect(!model.isLoading)
        #expect(model.emptyState == .noFiles)
    }

    @Test func loadMoreNeedsAChannel() async {
        let (model, recorder) = model()
        await model.loadMore()
        #expect(recorder.calls.isEmpty)
    }

    @Test func filterPersistsAcrossChannelsAndReloads() async {
        let (model, recorder) = model()
        await model.open(channelId: "c1")
        await model.select(filter: .images)
        await model.select(filter: .images)
        #expect(recorder.calls.count == 2)
        #expect(recorder.calls.last?.query.terms == "channel:c1 ext:png ext:jpg ext:jpeg ext:bmp ext:tiff ext:svg ext:xcf")
        await model.open(channelId: "c2")
        #expect(model.filter == .images)
        #expect(recorder.calls.last?.query == ChannelFileQuery(channelId: "c2", filter: .images))
        #expect(model.emptyState == .noFilteredFiles)
    }

    @Test func searchAppliesTrimmedTextUntilCleared() async {
        let (model, recorder) = model()
        await model.open(channelId: "c1")
        #expect(model.title == "Recent files")
        model.searchText = "  report "
        #expect(model.query.text.isEmpty)
        await model.submitSearch()
        #expect(model.title == "Search Results")
        #expect(recorder.calls.last?.query.terms == "report channel:c1")
        #expect(model.emptyState == .noResults("report"))
        await model.clearSearch()
        #expect(model.searchText.isEmpty)
        #expect(model.title == "Recent files")
        #expect(recorder.calls.count == 3)
        await model.clearSearch()
        #expect(recorder.calls.count == 3)
        model.searchText = "x"
        await model.open(channelId: "c1")
        #expect(model.searchText.isEmpty)
    }

    @Test func staleResponsesAreDropped() async {
        let (model, recorder) = model()
        recorder.pages = [0: FileFetchRecorder.files(1...2)]
        recorder.holdNext = true
        let slow = Task { await model.open(channelId: "c1") }
        while recorder.gate == nil { await Task.yield() }
        #expect(model.isLoading)
        #expect(model.emptyState == nil)
        recorder.pages = [0: FileFetchRecorder.files(5...5, prefix: "g")]
        await model.open(channelId: "c2")
        recorder.release()
        await slow.value
        #expect(model.channelId == "c2")
        #expect(model.files.map(\.id) == ["g5"])
    }

    @Test func staleLoadMoreIsDropped() async {
        let (model, recorder) = model()
        recorder.pages = [0: FileFetchRecorder.files(1...3), 1: FileFetchRecorder.files(4...6)]
        await model.open(channelId: "c1")
        recorder.holdNext = true
        let more = Task { await model.loadMore() }
        while recorder.gate == nil { await Task.yield() }
        #expect(model.isLoadingMore)
        await model.loadMore()
        #expect(recorder.calls.count == 2)
        recorder.pages = [0: FileFetchRecorder.files(9...9)]
        await model.reload()
        recorder.release()
        await more.value
        #expect(model.files.map(\.id) == ["f9"])
        #expect(!model.isLoadingMore)
    }
}

@Suite struct ChannelFilesEmptyStateTests {
    @Test func usesWebappWording() {
        #expect(ChannelFilesEmptyState(query: ChannelFileQuery(channelId: "c")) == .noFiles)
        #expect(ChannelFilesEmptyState.noFiles.title == "No files yet")
        #expect(ChannelFilesEmptyState.noFiles.subtitle == "Files posted in this channel will show here.")
        #expect(ChannelFilesEmptyState(query: ChannelFileQuery(channelId: "c", filter: .code)) == .noFilteredFiles)
        #expect(ChannelFilesEmptyState.noFilteredFiles.title == "No files found")
        #expect(ChannelFilesEmptyState.noFilteredFiles.subtitle == "This channel doesn't contains any file with the selected file format.")
        let results = ChannelFilesEmptyState(query: ChannelFileQuery(channelId: "c", text: " budget ", filter: .code))
        #expect(results == .noResults("budget"))
        #expect(results.title == "No file results for “budget”")
        #expect(results.subtitle == "Check the spelling or try another search.")
        #expect(ChannelFilesEmptyState.noFiles.systemImage != results.systemImage)
        #expect(ChannelFilesEmptyState.noFilteredFiles.systemImage == ChannelFilesEmptyState.noFiles.systemImage)
    }
}

@Suite struct ChannelFileFormattingTests {
    @Test(arguments: [
        (Int64(0), "0 B"), (1023, "1023 B"), (1024, "1024 B"), (1025, "1 KB"), (182_000, "177 KB"),
        (1_048_576, "1024 KB"), (2_400_000, "2 MB"), (1_073_741_825, "1 GB"), (3_298_534_883_329, "3 TB"),
    ])
    func sizeMatchesWebapp(bytes: Int64, text: String) {
        #expect(ChannelFileFormatting.size(bytes) == text)
    }

    @Test func dateUsesWebappRanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 18))!
        func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int, year: Int = 2026) -> String {
            ChannelFileFormatting.date(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!, now: now, calendar: calendar)
        }
        #expect(at(10, 24, 15, 45) == "Today at 3:45 PM")
        #expect(at(10, 23, 9, 5) == "Yesterday at 9:05 AM")
        #expect(at(10, 21, 12, 0) == "Wednesday at 12:00 PM")
        #expect(at(10, 18, 0, 30) == "Sunday at 12:30 AM")
        #expect(at(10, 17, 8, 0) == "October 17 at 8:00 AM")
        #expect(at(3, 5, 8, 0) == "March 05 at 8:00 AM")
        #expect(at(12, 31, 23, 59, year: 2025) == "December 31, 2025 at 11:59 PM")
    }
}
