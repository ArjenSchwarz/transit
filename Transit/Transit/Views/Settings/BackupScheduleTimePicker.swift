#if os(macOS)
import SwiftUI

/// Edits local wall-clock fields without interpreting them as an occurrence on today's date.
struct BackupScheduleTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        DatePicker("Daily at", selection: selection, displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .environment(\.timeZone, BackupSchedule.pickerTimeZone)
            .accessibilityIdentifier("backup.scheduleTime")
    }

    private var selection: Binding<Date> {
        Binding(
            get: { BackupSchedule(hour: hour, minute: minute).pickerDate },
            set: { date in
                let selected = BackupSchedule(pickerDate: date)
                hour = selected.hour
                minute = selected.minute
            })
    }
}
#endif
