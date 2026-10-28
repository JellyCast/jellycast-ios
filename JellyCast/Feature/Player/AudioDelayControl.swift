import SwiftUI

/// The lip-sync nudge for the Bluetooth device playing now: a slider and ±10 ms steps. Each change
/// makes the engine re-anchor at the playhead, so the slider applies its value on release only.
struct AudioDelayControl: View {
    let device: AudioDevice

    @State private var draft: Double?

    private static var cornerRadius: CGFloat { 18 }
    private var delay: AudioOutputDelay { .shared }
    private var saved: Int { delay.saved[device.id]?.milliseconds ?? 0 }
    private var shown: Int { draft.map { Int($0) } ?? saved }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.body.weight(.semibold)).foregroundStyle(JellyCastColors.text)
                    Text("Sound behind the picture? Move it until the lips match.")
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
                .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(shown) ms")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(JellyCastColors.text)
            }
            HStack(spacing: 12) {
                step("minus", by: -AudioOutputDelay.stepMilliseconds, label: "Less delay")
                Slider(
                    value: Binding(get: { Double(shown) }, set: { draft = $0 }),
                    in: 0...Double(AudioOutputDelay.maxMilliseconds),
                    step: Double(AudioOutputDelay.stepMilliseconds)
                ) { editing in
                    guard !editing, let draft else { return }
                    delay.set(Int(draft), for: device)
                    self.draft = nil
                }
                .tint(JellyCastColors.accent)
                step("plus", by: AudioOutputDelay.stepMilliseconds, label: "More delay")
            }
        }
        .padding(14)
        .background(JellyCastColors.text.opacity(0.05), in: .rect(cornerRadius: Self.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(JellyCastColors.text.opacity(0.1), lineWidth: 1.5)
        )
    }

    private func step(_ systemImage: String, by milliseconds: Int, label: LocalizedStringKey) -> some View {
        Button {
            delay.set(saved + milliseconds, for: device)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: 36, height: 36)
                .background(JellyCastColors.text.opacity(0.08), in: .circle)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .accessibilityLabel(label)
    }
}

#Preview {
    AudioDelayControl(device: AudioDevice(id: "preview", name: "BMW 23456"))
        .padding()
        .background(JellyCastColors.background)
}
