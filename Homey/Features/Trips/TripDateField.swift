import SwiftUI
import UIKit

/// Owns the calendar presentation so selecting a day dismisses only the calendar.
struct TripDateField: View {
    let title: String
    @Binding var selection: Date
    private let minimumDate: Date?
    private let maximumDate: Date?
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @State private var showsCalendar = false

    init(_ title: String, selection: Binding<Date>) {
        self.title = title; _selection = selection; minimumDate = nil; maximumDate = nil
    }
    init(_ title: String, selection: Binding<Date>, in range: PartialRangeFrom<Date>) {
        self.title = title; _selection = selection; minimumDate = range.lowerBound; maximumDate = nil
    }
    init(_ title: String, selection: Binding<Date>, in range: ClosedRange<Date>) {
        self.title = title; _selection = selection; minimumDate = range.lowerBound; maximumDate = range.upperBound
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(HomeyDashboardTheme.primaryText)
            Spacer()
            Button { showsCalendar = true } label: {
                Text(selection.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline).foregroundStyle(HomeyDashboardTheme.warmBrown)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(HomeyDashboardTheme.appBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selection.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showsCalendar) {
                TripInlineCalendar(selection: $selection, minimumDate: minimumDate, maximumDate: maximumDate,
                    calendar: calendar, locale: locale, timeZone: timeZone) { showsCalendar = false }
                    .frame(width: 320, height: 340).padding(12)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

private struct TripInlineCalendar: UIViewRepresentable {
    @Binding var selection: Date
    let minimumDate: Date?
    let maximumDate: Date?
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone
    let onSelected: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.tintColor = UIColor(HomeyDashboardTheme.warmBrown)
        picker.addTarget(context.coordinator, action: #selector(Coordinator.selected(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.calendar = calendar; picker.locale = locale; picker.timeZone = timeZone
        picker.minimumDate = minimumDate.map { calendar.startOfDay(for: $0) }
        picker.maximumDate = maximumDate.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))?.addingTimeInterval(-1)
        }
        picker.setDate(selection, animated: false)
    }
    final class Coordinator: NSObject {
        var parent: TripInlineCalendar
        init(parent: TripInlineCalendar) { self.parent = parent }
        @objc func selected(_ picker: UIDatePicker) {
            parent.selection = picker.date
            parent.onSelected()
        }
    }
}
