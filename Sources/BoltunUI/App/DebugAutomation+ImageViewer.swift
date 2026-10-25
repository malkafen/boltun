import Foundation

extension AutomationUIState {
    struct ImageViewerSummary: Codable, Equatable, Sendable {
        var fileId: String
        var name: String
        var index: Int
        var count: Int
        var width: Int
        var height: Int
        var zoom: String
        var fitting: Bool
        var quality: String?
        var decodedPixel: Int
        var loading: Bool
        var failure: String?
    }
}

extension DebugAutomation {
    static func imageViewerSummary(_ model: ImageViewerModel) -> AutomationUIState.ImageViewerSummary {
        AutomationUIState.ImageViewerSummary(
            fileId: model.file.id,
            name: model.file.name,
            index: model.index,
            count: model.gallery.count,
            width: Int(model.pixelSize.width),
            height: Int(model.pixelSize.height),
            zoom: model.zoom.percent,
            fitting: model.zoom.isFitting,
            quality: model.content.map { $0.quality == .full ? "full" : "preview" },
            decodedPixel: Int(model.decodedPixel),
            loading: model.isLoading,
            failure: model.failure
        )
    }
}
