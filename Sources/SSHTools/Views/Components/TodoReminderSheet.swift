import SwiftUI

struct TodoReminderSheet: View {
    @Binding var item: TodoItem
    @Binding var isPresented: Bool
    let onSave: (TodoItem) -> Void
    
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var frequency: ReminderFrequency
    @State private var customIntervalValue: Int = 30
    @State private var customIntervalUnit: TimeUnit = .minutes
    
    enum TimeUnit: String, CaseIterable {
        case minutes = "Minutes"
        case hours = "Hours"
    }
    
    init(item: Binding<TodoItem>, isPresented: Binding<Bool>, onSave: @escaping (TodoItem) -> Void) {
        self._item = item
        self._isPresented = isPresented
        self.onSave = onSave
        
        // Initialize state from item
        self._hasReminder = State(initialValue: item.wrappedValue.hasReminder)
        self._reminderDate = State(initialValue: item.wrappedValue.reminderDate ?? Date().addingTimeInterval(3600))
        self._frequency = State(initialValue: item.wrappedValue.reminderFrequency)
        
        if let interval = item.wrappedValue.reminderInterval {
            if interval >= 3600 && interval.truncatingRemainder(dividingBy: 3600) == 0 {
                self._customIntervalValue = State(initialValue: Int(interval / 3600))
                self._customIntervalUnit = State(initialValue: .hours)
            } else {
                self._customIntervalValue = State(initialValue: Int(interval / 60))
                self._customIntervalUnit = State(initialValue: .minutes)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Set Reminder".localized)
                .font(.headline)
            
            Toggle("Enable Reminder".localized, isOn: $hasReminder)
                .toggleStyle(.switch)
            
            if hasReminder {
                DatePicker("Time".localized, selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.stepperField)
                    .disabled(frequency == .custom) // Custom interval starts now/soon usually
                
                Picker("Frequency".localized, selection: $frequency) {
                    ForEach(ReminderFrequency.allCases, id: \.self) { freq in
                        Text(freq.localizedName).tag(freq)
                    }
                }
                .pickerStyle(.segmented)
                
                if frequency == .custom {
                    HStack {
                        TextField("Value", value: $customIntervalValue, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        
                        Picker("", selection: $customIntervalUnit) {
                            ForEach(TimeUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue.localized).tag(unit)
                            }
                        }
                        .frame(width: 100)
                        
                        Text("Interval".localized)
                    }
                }
            }
            
            HStack {
                Button("Cancel".localized) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save".localized) {
                    var updatedItem = item
                    updatedItem.hasReminder = hasReminder
                    if hasReminder {
                        updatedItem.reminderDate = reminderDate
                        updatedItem.reminderFrequency = frequency
                        
                        if frequency == .custom {
                            let multiplier: TimeInterval = customIntervalUnit == .minutes ? 60 : 3600
                            updatedItem.reminderInterval = TimeInterval(customIntervalValue) * multiplier
                        } else {
                            updatedItem.reminderInterval = nil
                        }
                    } else {
                        updatedItem.reminderDate = nil
                        updatedItem.reminderFrequency = .once
                        updatedItem.reminderInterval = nil
                    }
                    onSave(updatedItem)
                    isPresented = false
                }
                .buttonStyle(ModernButtonStyle(variant: .primary, size: .regular))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(width: 320)
        .background(DesignSystem.Colors.background)
    }
}
