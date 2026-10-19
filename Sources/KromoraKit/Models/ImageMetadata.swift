import Foundation
import ImageIO
import CoreGraphics

/// Photographic metadata pulled from a file's EXIF/TIFF/GPS dictionaries via
/// ImageIO, formatted for display in the info inspector.
///
/// This is a superset of `RecipeReport.CameraInfo` (which keeps only the few
/// tags the derive report cares about). Both read from the same
/// `CGImageSourceCopyPropertiesAtIndex` source — this one just surfaces the
/// common capture settings a photographer wants to see while grading.
struct ImageMetadata: Codable, Sendable, Equatable {

    // MARK: Camera & lens
    var make: String?
    var model: String?
    var lens: String?

    // MARK: Exposure
    var aperture: String?       // "ƒ/2.8"
    var shutterSpeed: String?   // "1/250 s"
    var iso: String?            // "ISO 400"
    var exposureBias: String?   // "+0.3 EV"
    var focalLength: String?    // "35 mm"
    var focalLength35: String?  // "52 mm" (35 mm-equivalent)
    var exposureProgram: String?
    var meteringMode: String?
    var flash: String?
    var whiteBalance: String?
    /// Numeric exposure values for Library range filtering (f-number, ISO, focal length in mm).
    var apertureValue: Double?
    var isoValue: Int?
    var focalLengthValue: Double?

    // MARK: Image
    var pixelWidth: Int?
    var pixelHeight: Int?
    var colorModel: String?     // "RGB"
    var colorProfile: String?   // "sRGB IEC61966-2.1", "Display P3", …
    var bitDepth: Int?          // bits per component

    // MARK: Capture
    var dateTaken: String?
    /// Sortable capture time for Library date filtering, "yyyy-MM-dd'T'HH:mm:ss" in the camera's
    /// local time (EXIF carries no zone). Empty when the file carries no valid capture date.
    var dateTakenISO: String = ""
    var software: String?

    // MARK: Location
    /// Validated numeric position of the loaded photo, for the Info panel's map. Session-only
    /// display state: it is never copied into `PhotoAssetMetadata` or the library index.
    var gpsCoordinate: GPSCoordinate?
    /// One-degree grid cell (~110 km) for Library filtering, e.g. "≈38° N, 122° W". Empty when
    /// the file carries no GPS; the precise coordinates are never copied into the index.
    var coarseLocation: String = ""

    var isEmpty: Bool {
        sections.isEmpty
    }

    // MARK: - Display sections

    struct Row: Identifiable, Codable, Sendable, Equatable {
        var id: String { label }
        let label: String
        let value: String
    }

    struct Section: Identifiable, Codable, Sendable, Equatable {
        var id: String { title }
        let title: String
        let rows: [Row]
    }

    /// Grouped, display-ready rows. Empty sections are dropped so the inspector
    /// only renders what the file actually carries.
    var sections: [Section] {
        var result: [Section] = []

        func section(_ title: String, _ pairs: [(String, String?)]) {
            let rows = pairs.compactMap { label, value in
                value.map { Row(label: label, value: $0) }
            }
            if !rows.isEmpty { result.append(Section(title: title, rows: rows)) }
        }

        let cameraName: String? = {
            let combined = [make, model].compactMap { $0 }.joined(separator: " ")
            return combined.isEmpty ? nil : combined
        }()

        section("Camera & Lens", [
            ("Camera", cameraName),
            ("Lens", lens),
        ])
        section("Exposure", [
            ("Aperture", aperture),
            ("Shutter", shutterSpeed),
            ("ISO", iso),
            ("Exp. Bias", exposureBias),
            ("Focal Length", focalLength),
            ("35mm Equiv.", focalLength35),
            ("Program", exposureProgram),
            ("Metering", meteringMode),
            ("Flash", flash),
            ("White Balance", whiteBalance),
        ])
        section("Image", [
            ("Dimensions", dimensionsLabel),
            ("Color Model", colorModel),
            ("Color Profile", colorProfile),
            ("Bit Depth", bitDepth.map { "\($0)-bit" }),
        ])
        section("Capture", [
            ("Date", dateTaken),
            ("Software", software),
        ])
        section("Location", [
            ("Latitude", gpsCoordinate?.latitudeLabel),
            ("Longitude", gpsCoordinate?.longitudeLabel),
        ])

        return result
    }

    /// The compact set of capture values used by the preview overlay. Values are already
    /// formatted for display by the metadata reader, and absent fields are omitted.
    var captureOverlayRows: [Row] {
        [
            ("ISO", iso),
            ("Shutter", shutterSpeed),
            ("Aperture", aperture),
            ("Focal length", focalLength),
        ].compactMap { label, value in
            value.map { Row(label: label, value: $0) }
        }
    }

    private var dimensionsLabel: String? {
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return nil }
        let mp = Double(w * h) / 1_000_000
        return "\(w) × \(h)  (\(String(format: "%.1f", mp)) MP)"
    }
}

// MARK: - GPS

/// A valid embedded GPS position. ImageIO reports magnitudes with separate N/S and E/W reference
/// letters, so the sign comes from the reference when present.
struct GPSCoordinate: Codable, Sendable, Hashable {
    let latitude: Double
    let longitude: Double

    /// Nil unless both values are finite and within ±90° / ±180°.
    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    init?(gps: [CFString: Any]) {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased()
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased()

        let latitude: Double
        switch latRef {
        case "N": latitude = abs(lat)
        case "S": latitude = -abs(lat)
        case nil: latitude = lat
        default: return nil
        }

        let longitude: Double
        switch lonRef {
        case "E": longitude = abs(lon)
        case "W": longitude = -abs(lon)
        case nil: longitude = lon
        default: return nil
        }

        self.init(latitude: latitude, longitude: longitude)
    }

    var latitudeLabel: String {
        String(format: "%.5f° %@", abs(latitude), latitude >= 0 ? "N" : "S")
    }

    var longitudeLabel: String {
        String(format: "%.5f° %@", abs(longitude), longitude >= 0 ? "E" : "W")
    }
}

// MARK: - Reading

extension ImageMetadata {

    /// Read metadata from a file URL.
    static func read(from url: URL) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return ImageMetadata()
        }
        return read(from: source)
    }

    /// Read metadata from in-memory image data (Photos imports, etc.).
    static func read(from data: Data) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ImageMetadata()
        }
        return read(from: source)
    }

    private static func read(from source: CGImageSource) -> ImageMetadata {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageMetadata()
        }

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps  = props[kCGImagePropertyGPSDictionary]  as? [CFString: Any] ?? [:]

        var m = ImageMetadata()

        // Camera & lens
        m.make  = trimmed(tiff[kCGImagePropertyTIFFMake] as? String)
        m.model = trimmed(tiff[kCGImagePropertyTIFFModel] as? String)
        m.lens  = trimmed(exif[kCGImagePropertyExifLensModel] as? String)
            ?? trimmed(exif[kCGImagePropertyExifLensMake] as? String)

        // Exposure
        if let f = exif[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            m.aperture = "ƒ/\(trimNumber(f))"
            m.apertureValue = f
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            m.shutterSpeed = formatShutter(t)
        }
        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArray.first {
            m.iso = "ISO \(iso)"
            m.isoValue = iso
        } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
            m.iso = "ISO \(iso)"
            m.isoValue = iso
        }
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double {
            m.exposureBias = abs(bias) < 0.05 ? "0 EV" : String(format: "%+.1f EV", bias)
        }
        if let fl = exif[kCGImagePropertyExifFocalLength] as? Double, fl > 0 {
            m.focalLength = "\(trimNumber(fl)) mm"
            m.focalLengthValue = fl
        }
        if let fl35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, fl35 > 0 {
            m.focalLength35 = "\(fl35) mm"
        }
        m.exposureProgram = exposureProgramLabel(exif[kCGImagePropertyExifExposureProgram] as? Int)
        m.meteringMode    = meteringModeLabel(exif[kCGImagePropertyExifMeteringMode] as? Int)
        m.flash           = flashLabel(exif[kCGImagePropertyExifFlash] as? Int)
        m.whiteBalance    = whiteBalanceLabel(exif[kCGImagePropertyExifWhiteBalance] as? Int)

        // Image. ImageIO reports the *stored* buffer dimensions; orientations
        // 5-8 are quarter-turns, so display dimensions are the transpose. The
        // app renders images upright (see ImageDecoder.orientedLoadOptions),
        // so report what the user actually sees.
        let orientation = (props[kCGImagePropertyOrientation] as? Int)
            ?? (tiff[kCGImagePropertyTIFFOrientation] as? Int)
            ?? 1
        let storedWidth = (props[kCGImagePropertyPixelWidth] as? Int)
            ?? (exif[kCGImagePropertyExifPixelXDimension] as? Int)
        let storedHeight = (props[kCGImagePropertyPixelHeight] as? Int)
            ?? (exif[kCGImagePropertyExifPixelYDimension] as? Int)
        let isQuarterTurned = (5...8).contains(orientation)
        m.pixelWidth  = isQuarterTurned ? storedHeight : storedWidth
        m.pixelHeight = isQuarterTurned ? storedWidth : storedHeight
        m.colorModel   = props[kCGImagePropertyColorModel] as? String
        m.colorProfile = props[kCGImagePropertyProfileName] as? String
        m.bitDepth     = props[kCGImagePropertyDepth] as? Int

        // Capture
        m.dateTaken = formatDate(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? formatDate(tiff[kCGImagePropertyTIFFDateTime] as? String)
        m.dateTakenISO = sortableDate(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? sortableDate(tiff[kCGImagePropertyTIFFDateTime] as? String) ?? ""
        m.software  = trimmed(tiff[kCGImagePropertyTIFFSoftware] as? String)

        // Location
        m.gpsCoordinate = GPSCoordinate(gps: gps)
        m.coarseLocation = coarseLocationCell(gps) ?? ""

        return m
    }

    // MARK: - Formatting helpers

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Drop a trailing ".0" so 8.0 → "8" but 2.8 stays "2.8".
    private static func trimNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return "\(trimNumber(seconds)) s"
        }
        let denom = Int((1.0 / seconds).rounded())
        return "1/\(denom) s"
    }

    /// EXIF dates are "yyyy:MM:dd HH:mm:ss"; reformat to something readable.
    private static func formatDate(_ raw: String?) -> String? {
        guard let raw = trimmed(raw) else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    /// EXIF "yyyy:MM:dd HH:mm:ss" → "yyyy-MM-dd'T'HH:mm:ss", or nil when malformed (including the
    /// all-zero placeholder some cameras write).
    static func sortableDate(_ raw: String?) -> String? {
        guard let raw = trimmed(raw) else { return nil }
        let characters = Array(raw)
        guard characters.count == 19, characters[4] == ":", characters[7] == ":",
              characters[10] == " ", characters[13] == ":", characters[16] == ":"
        else { return nil }
        func component(_ range: Range<Int>) -> Int? {
            let digits = characters[range]
            guard digits.allSatisfy(\.isNumber) else { return nil }
            return Int(String(digits))
        }
        guard let year = component(0..<4), let month = component(5..<7),
              let day = component(8..<10), let hour = component(11..<13),
              let minute = component(14..<16), let second = component(17..<19),
              (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysInMonth(month, year: year)).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else { return nil }
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            year, month, day, hour, minute, second)
    }

    static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: (year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Rounds to whole degrees on-device. No geocoder or network lookup is involved.
    private static func coarseLocationCell(_ gps: [CFString: Any]) -> String? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
              lat.isFinite, lon.isFinite,
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? (lat >= 0 ? "N" : "S")
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? (lon >= 0 ? "E" : "W")
        return "≈\(Int(abs(lat).rounded()))° \(latRef), \(Int(abs(lon).rounded()))° \(lonRef)"
    }

    private static func exposureProgramLabel(_ v: Int?) -> String? {
        switch v {
        case 1: return "Manual"
        case 2: return "Program AE"
        case 3: return "Aperture Priority"
        case 4: return "Shutter Priority"
        case 5: return "Creative"
        case 6: return "Action"
        case 7: return "Portrait"
        case 8: return "Landscape"
        default: return nil
        }
    }

    private static func meteringModeLabel(_ v: Int?) -> String? {
        switch v {
        case 1: return "Average"
        case 2: return "Center-weighted"
        case 3: return "Spot"
        case 4: return "Multi-spot"
        case 5: return "Multi-segment"
        case 6: return "Partial"
        default: return nil
        }
    }

    private static func flashLabel(_ v: Int?) -> String? {
        guard let v else { return nil }
        return (v & 0x1) == 1 ? "Fired" : "Did not fire"
    }

    private static func whiteBalanceLabel(_ v: Int?) -> String? {
        switch v {
        case 0: return "Auto"
        case 1: return "Manual"
        default: return nil
        }
    }
}
