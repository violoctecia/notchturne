import SwiftUI

struct SettingsPanel: View {
    @ObservedObject var settings: Settings
    @ObservedObject var calendar: CalendarProvider
    @ObservedObject var clipboard: ClipboardProvider

    @State private var confirmingQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(settings.text.whatToShow)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .kerning(0.6)
                .padding(.bottom, 8)

            toggleRow(settings.text.lyrics, isOn: $settings.lyrics)
            toggleRow(settings.text.calendar, isOn: $settings.calendar)
            toggleRow(settings.text.clipboard, isOn: $settings.clipboard)
            toggleRow(settings.text.artworkLookup, isOn: $settings.artworkLookup)

            toggleRow(settings.text.menuBarIcon, isOn: $settings.menuBarIcon)

            row(settings.text.clipboardLimit) {
                Stepper(value: $settings.clipboardLimit, range: 1...10)
            }
            row(settings.text.activationDelay) {
                Stepper(value: $settings.activationDelay, range: 0...500, step: 50,
                        unit: settings.text.msUnit)
            }
            row(settings.text.language_) {
                Segmented(selection: $settings.language)
            }

            Spacer(minLength: 12)

            quitButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quitButton: some View {
        Button(action: quitTapped) {
            Text(confirmingQuit ? settings.text.quitConfirm : settings.text.quit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(confirmingQuit ? Color(red: 1, green: 0.45, blue: 0.42)
                                                : .white.opacity(0.5))
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(confirmingQuit ? Color(red: 1, green: 0.3, blue: 0.28).opacity(0.16)
                                             : .white.opacity(0.07))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: confirmingQuit)
    }

    private func quitTapped() {
        guard confirmingQuit else {
            confirmingQuit = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmingQuit = false }
            return
        }
        NSApp.terminate(nil)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) { Switcher(isOn: isOn) }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
                    isOn.wrappedValue.toggle()
                }
            }
    }

    private func row<Trailing: View>(_ title: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        }
    }
}

private struct Switcher: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.green : Color.white.opacity(0.15))
            .frame(width: 30, height: 17)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .offset(x: isOn ? 6.5 : -6.5)
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isOn)
    }
}

private struct Stepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: unit.isEmpty ? 22 : 44)
            button("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private func button(_ symbol: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(enabled ? 0.75 : 0.2))
            .frame(width: 22, height: 18)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

private struct Segmented: View {
    @Binding var selection: Language

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Language.allCases) { language in
                let active = selection == language
                Text(language.short)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? .black : .white.opacity(0.55))
                    .frame(width: 40, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(active ? Color.white : Color.white.opacity(0.08))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.16)) { selection = language }
                    }
            }
        }
    }
}
