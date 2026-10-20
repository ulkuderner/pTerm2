import SwiftTerm
import SwiftUI

struct ThemeGallery: View {
    @State private var themeID = TerminalTheme.current.id

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(TerminalTheme.allCases) { theme in
                    Button {
                        TerminalTheme.current = theme
                        themeID = theme.id
                    } label: {
                        ThemeCard(theme: theme, selected: theme.id == themeID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme.id == themeID ? .isSelected : [])
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Pad.Theme.Title",
                                defaultValue: "Themes",
                                comment: "Title of the terminal theme gallery"))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .terminalThemeChanged)) { note in
            if let id = note.object as? String {
                themeID = id
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: TerminalTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: theme.background))
                .overlay(alignment: .topLeading) {
                    Text("❯ shell")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(uiColor: theme.foreground))
                        .padding(10)
                }
                .frame(height: 72)
            HStack(spacing: 4) {
                ForEach(Array(theme.palette.prefix(8).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(Color(uiColor: Self.swatch(color)))
                        .frame(width: 12, height: 12)
                }
            }
            Text(theme.title)
                .font(.headline)
                .foregroundStyle(Color.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2 : 1)
        }
    }

    private static func swatch(_ color: SwiftTerm.Color) -> UIColor {
        UIColor(red: CGFloat(color.red) / 65535,
                green: CGFloat(color.green) / 65535,
                blue: CGFloat(color.blue) / 65535,
                alpha: 1)
    }
}
