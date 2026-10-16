import Foundation

/// sRGB relative luminance, not a weighted average of gamma-encoded channels.
struct ContrastRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let black = Self(red: 0, green: 0, blue: 0)
    static let white = Self(red: 1, green: 1, blue: 1)

    var luminance: Double {
        func linear(_ value: Double) -> Double {
            let value = min(max(value, 0), 1)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    func mixed(with other: Self, amount: Double) -> Self {
        Self(red: red + (other.red - red) * amount,
             green: green + (other.green - green) * amount,
             blue: blue + (other.blue - blue) * amount)
    }

    func readable(on background: Self, minimum: Double = 4.5) -> Self {
        if contrast(with: background) >= minimum { return self }
        let endpoint: Self = Self.black.contrast(with: background) >= Self.white.contrast(with: background) ? .black : .white
        for step in 1...100 {
            let candidate = mixed(with: endpoint, amount: Double(step) / 100)
            if candidate.contrast(with: background) >= minimum { return candidate }
        }
        return endpoint
    }

    var buttonLabel: Self {
        // Retain the accent hue while making the label clearly distinct from its fill.
        mixed(with: .black, amount: 0.78).readable(on: self)
    }
}
