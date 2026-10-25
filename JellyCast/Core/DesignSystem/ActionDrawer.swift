import SwiftUI

/// One choice in the drawer a long press opens.
struct DrawerAction: Identifiable {
    let title: String
    let systemImage: String
    var isAccented = false
    let perform: () -> Void

    var id: String { title }
}

/// What the drawer shows above its choices: the item it acts on.
struct DrawerHeader {
    let title: String
    var subtitle: String?
    var image: ImageRef?
    var imageType = JellyfinClient.ImageType.primary
    var isWide = false
}

extension View {
    /// A long press opens a drawer from the bottom with these choices. A choice runs once the
    /// drawer is gone, so it can play, navigate or open another sheet.
    func actionDrawer(_ header: DrawerHeader, actions: [DrawerAction]) -> some View {
        modifier(ActionDrawerModifier(header: header, actions: actions))
    }
}

private struct ActionDrawerModifier: ViewModifier {
    let header: DrawerHeader
    let actions: [DrawerAction]

    @State private var isPresented = false
    @State private var chosen: DrawerAction?

    private static let pressSeconds = 0.4

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                LongPressGesture(minimumDuration: Self.pressSeconds).onEnded { _ in isPresented = true }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: isPresented) { _, presented in presented }
            .accessibilityAction(named: "More") { isPresented = true }
            .sheet(isPresented: $isPresented, onDismiss: runChosen) {
                ActionDrawerSheet(header: header, actions: actions) { action in
                    chosen = action
                    isPresented = false
                }
            }
    }

    private func runChosen() {
        guard let chosen else { return }
        self.chosen = nil
        chosen.perform()
    }
}

private struct ActionDrawerSheet: View {
    let header: DrawerHeader
    let actions: [DrawerAction]
    let onChoose: (DrawerAction) -> Void

    @State private var height: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DrawerHeaderView(header: header).padding(.bottom, 6)
            ForEach(actions) { action in
                SheetRow(title: action.title, systemImage: action.systemImage, isAccented: action.isAccented) {
                    onChoose(action)
                } trailing: {
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }
}

private struct DrawerHeaderView: View {
    let header: DrawerHeader

    private static let posterSize = CGSize(width: 44, height: 66)
    private static let wideSize = CGSize(width: 96, height: 54)

    var body: some View {
        let size = header.isWide ? Self.wideSize : Self.posterSize
        HStack(spacing: 14) {
            RemoteImage(ref: header.image, type: header.imageType, width: size.width)
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(header.title)
                    .font(.headline)
                    .foregroundStyle(JellyCastColors.text)
                    .lineLimit(2)
                if let subtitle = header.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.textMuted)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview {
    Text("Hold me")
        .foregroundStyle(JellyCastColors.text)
        .actionDrawer(
            DrawerHeader(title: "Interstellar", subtitle: "2014 · Movie"),
            actions: [
                DrawerAction(title: "Play", systemImage: "play.fill", isAccented: true) {},
                DrawerAction(title: "Mark as watched", systemImage: "checkmark.circle") {},
            ]
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JellyCastColors.background)
        .preferredColorScheme(.dark)
}
