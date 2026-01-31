import SwiftUI

/// View for rating workout effort on a 1-10 scale
struct EffortRatingView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var effortRating: Int?
    @State private var selectedRating: Int
    
    
    
    // Effort descriptions matching Nike Run Club
    private let effortDescriptions: [Int: (title: String, description: String)] = [
        1: ("Extremely light", "Walking slowly"),
        2: ("Very light", "Brisk walk"),
        3: ("Light", "Speed walking"),
        4: ("Moderate", "Slow jog, able to talk"),
        5: ("Somewhat hard", "Steady run"),
        6: ("Challenging", "Breathing hard, not talking much"),
        7: ("Hard", "Tough to maintain"),
        8: ("Very hard", "Very tough"),
        9: ("Extremely hard", "Max sustainable effort"),
        10: ("Max effort", "Hardest I can possibly work")
    ]
    
    init(effortRating: Binding<Int?>) {
        self._effortRating = effortRating
        self._selectedRating = State(initialValue: effortRating.wrappedValue ?? 6)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.strideBlack.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Large number display
                    VStack(spacing: 16) {
                        Text("\(selectedRating)")
                            .font(.system(size: 120, weight: .medium))
                            .foregroundColor(.white)
                        
                        if let desc = effortDescriptions[selectedRating] {
                            Text(desc.title.uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .tracking(2)
                            
                            Text(desc.description)
                                .font(.system(size: 16, weight: .light))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Slider scale
                    VStack(spacing: 16) {
                        // Custom slider
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 4)
                                
                                // Active track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.stridePrimary)
                                    .frame(width: geometry.size.width * CGFloat(selectedRating - 1) / 9.0, height: 4)
                                
                                // Thumb
                                Circle()
                                    .fill(Color.stridePrimary)
                                    .frame(width: 28, height: 28)
                                    .offset(x: geometry.size.width * CGFloat(selectedRating - 1) / 9.0 - 14)
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let newValue = min(max(1, Int((value.location.x / geometry.size.width) * 10) + 1), 10)
                                                selectedRating = newValue
                                            }
                                    )
                            }
                        }
                        .frame(height: 28)
                        .padding(.horizontal, 40)
                        
                        // Number labels
                        HStack(spacing: 0) {
                            ForEach(1...10, id: \.self) { number in
                                Text("\(number)")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(number == selectedRating ? .stridePrimary : .gray)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 60)
                }
            }
            .navigationTitle("My effort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.stridePrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        effortRating = selectedRating
                        dismiss()
                    }
                    .foregroundColor(.stridePrimary)
                    .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}



