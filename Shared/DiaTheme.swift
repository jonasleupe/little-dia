import SwiftUI
import UIKit

/// Design tokens lifted from the "Dia for iOS" Figma file. Light values are the
/// source of truth; dark values are derived so the sheet stays legible at night.
enum DiaTheme {

    // MARK: Colors

    /// Outer sheet: #EBEBEB at 82% over white.
    static let sheetBackground = adaptive(light: 0xEDEDED, dark: 0x1C1C1E)
    /// Inner white sheet + composer.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// Dashed content border #D6D6D6.
    static let dashedBorder = adaptive(light: 0xD6D6D6, dark: 0x48484A)
    /// Secondary label / toolbar close icon #727272.
    static let secondaryLabel = adaptive(light: 0x727272, dark: 0xA1A1A6)
    /// Placeholder + disabled glyphs #B3B4B4.
    static let placeholder = adaptive(light: 0xB3B4B4, dark: 0x6E6E73)
    /// Send button background (Figma #F2F3F3, nudged darker so the circle reads on white).
    static let sendBackground = adaptive(light: 0xE9EAEA, dark: 0x3A3A3C)
    /// Send arrow when there's nothing to send yet.
    static let sendIdleGlyph = adaptive(light: 0x8E8F8F, dark: 0x8E8E93)
    /// User bubble #F1F2F4.
    static let userBubble = adaptive(light: 0xF1F2F4, dark: 0x3A3A3C)
    /// Section icon pill #EFEFEF.
    static let iconPill = adaptive(light: 0xEFEFEF, dark: 0x3A3A3C)
    /// Bookmark button #4C4C4C.
    static let bookmark = adaptive(light: 0x4C4C4C, dark: 0xE5E5EA)
    /// Primary text.
    static let label = adaptive(light: 0x000000, dark: 0xFFFFFF)
    /// Toolbar title #1A1A1A.
    static let title = adaptive(light: 0x1A1A1A, dark: 0xFFFFFF)
    /// Sheet grabber (Fills/Vibrant/Primary, #CCCCCC).
    static let grabber = adaptive(light: 0xCCCCCC, dark: 0x5A5A5E)
    /// Card hairline.
    static let hairline = adaptive(light: 0xE6E6E6, dark: 0x3A3A3C)

    /// "Summarized for you by Dia" — 60% black.
    static var captionLabel: Color { label.opacity(0.6) }

    /// Blurred rainbow bleed behind the outer sheet (Rectangle 104 in Figma).
    static let bleedGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x340B05), location: 0),
            .init(color: Color(hex: 0x0358F7), location: 0.18),
            .init(color: Color(hex: 0x5092C7), location: 0.28),
            .init(color: Color(hex: 0xE1ECFE), location: 0.41),
            .init(color: Color(hex: 0xFFD400), location: 0.59),
            .init(color: Color(hex: 0xFA3D1D), location: 0.68),
            .init(color: Color(hex: 0xFD02F5), location: 0.80),
            .init(color: .white, location: 1),
        ],
        startPoint: .bottom, endPoint: .top
    )

    // MARK: Typography

    /// 16pt / 21 leading / −0.112 tracking.
    static let body = Font.system(size: 16)
    static let bodySemibold = Font.system(size: 16, weight: .semibold)
    static let bodyLineSpacing: CGFloat = 5
    static let bodyTracking: CGFloat = -0.112
    /// 12pt / 21 leading.
    static let caption = Font.system(size: 12)
    static let captionTracking: CGFloat = -0.084
    /// 17pt composer text.
    static let input = Font.system(size: 17)
    /// 17pt semibold toolbar title.
    static let headline = Font.system(size: 17, weight: .semibold)

    // MARK: Radii & metrics

    static let sheetRadius: CGFloat = 38
    static let contentRadius: CGFloat = 30
    static let composerRadius: CGFloat = 24
    static let cardRadius: CGFloat = 22
    static let buttonRadius: CGFloat = 18
    static let bubbleRadius: CGFloat = 14
    static let toolbarButton: CGFloat = 36
    static let contentInset: CGFloat = 16

    // MARK: Helpers

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}

/// Body text styled exactly like the design's 16/21 paragraph.
struct DiaBodyText: View {
    let text: String
    var weight: Font.Weight = .regular

    init(_ text: String, weight: Font.Weight = .regular) {
        self.text = text
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: weight))
            .tracking(DiaTheme.bodyTracking)
            .lineSpacing(DiaTheme.bodyLineSpacing)
            .foregroundStyle(DiaTheme.label)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Dia mark with a caption next to it ("Summarized for you by Dia", "Thought for 14s").
struct DiaCaptionRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image("DiaMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
            Text(text)
                .font(DiaTheme.caption)
                .tracking(DiaTheme.captionTracking)
                .foregroundStyle(DiaTheme.captionLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
