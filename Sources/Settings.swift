import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @AppStorage("iliad.fontSize") private var fontSize: Double = 20
    @AppStorage("iliad.lineHeight") private var lineHeight: Double = 1.3
    @AppStorage("iliad.measure") private var measure: Double = 680

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Writing font", selection: Binding(get: { theme.fontName }, set: { theme.setFont($0) })) {
                    ForEach(Fonts.writingFonts, id: \.self) { Text($0).tag($0) }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Font size: \(Int(fontSize)) pt").font(.caption)
                    Slider(value: $fontSize, in: 13...32, step: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "Line height: %.2f×", lineHeight)).font(.caption)
                    Slider(value: $lineHeight, in: 1.0...2.2, step: 0.05)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Line width: \(Int(measure)) pt").font(.caption)
                    Slider(value: $measure, in: 480...1000, step: 20)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paragraph weight: \(Int(theme.bodyWeight))").font(.caption)
                    Slider(value: Binding(get: { theme.bodyWeight }, set: { theme.bodyWeight = $0 }), in: 200...500, step: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Title weight: \(Int(theme.headingWeight))").font(.caption)
                    Slider(value: Binding(get: { theme.headingWeight }, set: { theme.headingWeight = $0 }), in: 300...800, step: 10)
                }
            }
            Section("Theme") {
                HStack {
                    Text("Current: \(theme.currentName)")
                    Spacer()
                    Button("Import Terminal Theme…") { theme.importThemes() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.vertical, 6)
    }
}
