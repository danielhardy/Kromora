import Foundation

/// Info inspector state: the loaded image's metadata and the histogram of the displayed image.
///
/// A histogram refresh happens on most edits, so this lives apart from `AppViewModel`: views that
/// read it track only these properties. The histogram gate and scheduling stay with the owner.
@MainActor
@Observable
final class InfoState {
    /// EXIF/TIFF/GPS metadata of the loaded image, read at load time.
    var metadata = ImageMetadata()
    /// Histogram of the currently displayed image (graded result, or original while comparing).
    /// `nil` until computed / when no image is loaded.
    var histogram: HistogramData?
    /// A nil histogram is otherwise ambiguous: it can mean loading, cancellation, an
    /// unsupported source, or a failed calculation. Keep the terminal UI state explicit.
    private(set) var isHistogramLoading = false
    private(set) var histogramErrorMessage: String?

    func setHistogramLoading(_ isLoading: Bool) { isHistogramLoading = isLoading }
    func setHistogramError(_ message: String?) { histogramErrorMessage = message }
}
