import SwiftUI

/// Month and Year picker component with wheel UI
struct PeriodPickerView: View {
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    let showMonthPicker: Bool
    @Environment(\.dismiss) var dismiss
    
    private let months = Calendar.current.monthSymbols
    private let currentYear = Calendar.current.component(.year, from: Date())
    private var years: [Int] {
        // Generate years from 2020 to current year
        Array((2020...currentYear).reversed())
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pickers
                HStack(spacing: 40) {
                    if showMonthPicker {
                        // Month picker
                        Picker("Month", selection: $selectedMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(months[month - 1])
                                    .tag(month)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Year picker
                    Picker("Year", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year))
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Select period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}

/// Compact display of selected month/year with dropdown indicator
struct PeriodDisplayView: View {
    let month: Int
    let year: Int
    let isVisible: Bool
    let showMonthAndYear: Bool
    let action: () -> Void
    
    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        var components = DateComponents()
        components.month = month
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return ""
    }
    
    private var displayText: String {
        if showMonthAndYear {
            return "\(monthName) \(year)"
        } else {
            return "\(year)"
        }
    }
    
    var body: some View {
        if isVisible {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(displayText)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }
            .padding(.vertical, 8)
        }
    }
}

