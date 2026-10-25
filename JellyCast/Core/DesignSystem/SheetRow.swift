import SwiftUI

/// One choice in a sheet: "Play on…", audio and subtitles, quality.
struct SheetRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var isAccented = false
    let action: () -> Void
    @ViewBuilder var trailing: Trailing

    private static var cornerRadius: CGFloat { 18 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.12), in: .circle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(JellyCastColors.text)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(14)
            .frame(minHeight: 56)
            .background(JellyCastColors.text.opacity(0.05), in: .rect(cornerRadius: Self.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(JellyCastColors.text.opacity(0.1), lineWidth: 1.5)
            )
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }

    private var tint: Color { isAccented ? JellyCastColors.accent : JellyCastColors.text }
}

/// A row that is chosen or not, with a check on the chosen one.
struct CheckedSheetRow: View {
    let title: String
    var detail: String?
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        SheetRow(title: title, detail: detail, action: action) {
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(JellyCastColors.accent)
            }
        }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// The title on top of a sheet, with an optional line under it.
struct SheetTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold()).foregroundStyle(JellyCastColors.text)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 14) {
        SheetTitle(title: "Audio and subtitles", subtitle: "The Pacific")
        SheetRow(title: "Living room", detail: "JellyCast is open", systemImage: "tv", isAccented: true) {} trailing: {
            Image(systemName: "play.fill").foregroundStyle(JellyCastColors.text)
        }
        CheckedSheetRow(title: "English", detail: "TrueHD Atmos 7.1", isChecked: true) {}
        CheckedSheetRow(title: "Dutch", detail: "AC3 5.1", isChecked: false) {}
    }
    .padding(20)
    .background(JellyCastColors.background)
    .preferredColorScheme(.dark)
}
