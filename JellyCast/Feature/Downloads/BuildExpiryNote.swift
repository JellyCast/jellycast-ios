import SwiftUI

/// Until when this build opens. Close to the date it warns, because a download is no use on a
/// trip once the app won't launch.
struct BuildExpiryNote: View {
    let date: Date

    var body: some View {
        let isSoon = BuildExpiry.isSoon(date)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSoon ? "exclamationmark.triangle.fill" : "clock")
                .foregroundStyle(isSoon ? JellyCastColors.accent : JellyCastColors.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("This app opens until \(date, format: .dateTime.weekday(.wide).day().month().hour().minute())")
                    .foregroundStyle(isSoon ? JellyCastColors.text : JellyCastColors.textMuted)
                if isSoon {
                    Text("Reinstall it from the Mac before you travel, or your downloads won't open.")
                        .foregroundStyle(JellyCastColors.textMuted)
                }
            }
        }
        .font(.footnote)
        .padding(.vertical, isSoon ? 12 : 4)
        .padding(.horizontal, isSoon ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSoon { RoundedRectangle(cornerRadius: 12).fill(JellyCastColors.surface) }
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack(spacing: 16) {
        BuildExpiryNote(date: .now.addingTimeInterval(6 * 24 * 60 * 60))
        BuildExpiryNote(date: .now.addingTimeInterval(36 * 60 * 60))
    }
    .padding()
    .background(JellyCastColors.background)
}
