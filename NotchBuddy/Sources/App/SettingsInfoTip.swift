import SwiftUI

/// Info icon with instant hover tooltip (`.help`) and click-toggleable popover card.
struct SettingsInfoTip: View {
    let title: String?
    let text: String

    init(title: String? = nil, text: String) {
        self.title = title
        self.text = text
    }

    @State private var isPopoverPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(isPopoverPresented ? Color.accentColor : (isHovered ? Color.primary : Color.secondary.opacity(0.7)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 270)
        }
    }
}
