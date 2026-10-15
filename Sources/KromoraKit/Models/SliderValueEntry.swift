import Foundation

/// Parses and validates a number a photographer typed into a slider's value field.
///
/// The rule has one source: the slider's own `range` and `step`. Typed text is read in the control's
/// display units (`displayScale` maps a stored value to what the readout shows, so a 0…1 intensity
/// is typed as 0…100). Out-of-range input is rejected, never clamped.
struct SliderValueEntry: Equatable, Sendable {
    enum Failure: Error, Equatable, Sendable {
        case empty
        case notANumber
        /// Carries the formatted bounds so the message reads "Enter -100 to 100".
        case outOfRange(lower: String, upper: String)

        var message: String {
            switch self {
            case .empty: return "Enter a number"
            case .notANumber: return "Not a number"
            case .outOfRange(let lower, let upper): return "Enter \(lower) to \(upper)"
            }
        }
    }

    let range: ClosedRange<Double>
    let step: Double?
    /// Multiplier from stored value to displayed value (100 for a 0…1 amount shown as a percent).
    let displayScale: Double
    /// The stored value that displays as zero (the range's lower bound for a position-in-range
    /// percentage; 0 for everything else).
    let displayOrigin: Double
    /// Digits shown when the field is pre-filled, and used to word the bounds in the error.
    let fractionDigits: Int
    /// Optional unit text accepted after the number, such as `EV`, `K`, `°`, `%` or `px`.
    let unit: String
    let locale: Locale

    init(
        range: ClosedRange<Double>,
        step: Double? = nil,
        displayScale: Double = 1,
        displayOrigin: Double = 0,
        fractionDigits: Int = 0,
        unit: String = "",
        locale: Locale = .current
    ) {
        self.range = range
        self.step = step
        self.displayScale = displayScale
        self.displayOrigin = displayOrigin
        self.fractionDigits = fractionDigits
        self.unit = unit
        self.locale = locale
    }

    private var displayRange: ClosedRange<Double> {
        (range.lowerBound - displayOrigin) * displayScale...(range.upperBound - displayOrigin) * displayScale
    }

    private func formatStyle() -> FloatingPointFormatStyle<Double> {
        .number.locale(locale).precision(.fractionLength(0...max(fractionDigits, 0))).grouping(.never)
    }

    /// The text a field is pre-filled with: the displayed number, no sign and no unit.
    func editingText(for storedValue: Double) -> String {
        ((storedValue - displayOrigin) * displayScale).formatted(formatStyle())
    }

    func parse(_ text: String) -> Result<Double, Failure> {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty {
            let suffix = unit.trimmingCharacters(in: .whitespaces)
            if let found = body.range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) {
                body.removeSubrange(found)
                body = body.trimmingCharacters(in: .whitespaces)
            }
        }
        if body.hasPrefix("+") {
            body.removeFirst()
            if body.hasPrefix("-") { return .failure(.notANumber) }
        }
        guard !body.isEmpty else { return .failure(.empty) }
        // Foundation's parser accepts a numeric prefix ("1x" -> 1), so check the whole string.
        let separator = locale.decimalSeparator ?? "."
        let digits = body.hasPrefix("-") ? body.dropFirst() : Substring(body)
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber || String($0) == separator }),
              digits.filter({ String($0) == separator }).count <= 1,
              let number = try? Double(body, format: FloatingPointFormatStyle<Double>.number.locale(locale)),
              number.isFinite
        else { return .failure(.notANumber) }

        // Allow only a few floating-point rounding units from the scale/origin conversion above.
        // A relative epsilon here let real out-of-range inputs pass and then get clamped.
        let tolerance = 8 * max(
            Double.ulpOfOne,
            displayRange.lowerBound.ulp,
            displayRange.upperBound.ulp
        )
        guard number >= displayRange.lowerBound - tolerance,
              number <= displayRange.upperBound + tolerance
        else {
            let style = formatStyle()
            return .failure(.outOfRange(
                lower: displayRange.lowerBound.formatted(style),
                upper: displayRange.upperBound.formatted(style)
            ))
        }
        return .success(snapped(number / displayScale + displayOrigin))
    }

    /// Snaps to the control's step, anchored at the range's lower bound like the slider itself.
    func snapped(_ value: Double) -> Double {
        var result = min(max(value, range.lowerBound), range.upperBound)
        if let step, step.isFinite, step > 0 {
            result = range.lowerBound + ((result - range.lowerBound) / step).rounded() * step
            result = min(max(result, range.lowerBound), range.upperBound)
            // Remove accumulated binary noise such as 0.30000000000000004.
            result = (result * 1e9).rounded() / 1e9
        }
        return result
    }

    /// The spoken/displayed form of a committed value.
    func announcement(for storedValue: Double) -> String {
        let text = editingText(for: storedValue)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}
