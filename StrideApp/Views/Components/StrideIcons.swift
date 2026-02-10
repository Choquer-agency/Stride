import SwiftUI

// MARK: - Stride Logo Shape
struct StrideLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (44x36)
        let scaleX = w / 44
        let scaleY = h / 36
        
        // Path 1 - Main body
        path.move(to: CGPoint(x: 4.17 * scaleX, y: 35.37 * scaleY))
        path.addCurve(
            to: CGPoint(x: 0.03 * scaleX, y: 31.12 * scaleY),
            control1: CGPoint(x: 1.96 * scaleX, y: 35.04 * scaleY),
            control2: CGPoint(x: 0.28 * scaleX, y: 33.32 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 1.78 * scaleX, y: 26.70 * scaleY),
            control1: CGPoint(x: -0.16 * scaleX, y: 29.46 * scaleY),
            control2: CGPoint(x: 0.49 * scaleX, y: 27.77 * scaleY)
        )
        path.addLine(to: CGPoint(x: 6.92 * scaleX, y: 22.46 * scaleY))
        path.addLine(to: CGPoint(x: 9.14 * scaleX, y: 20.63 * scaleY))
        path.addLine(to: CGPoint(x: 22.82 * scaleX, y: 9.37 * scaleY))
        path.addCurve(
            to: CGPoint(x: 26.60 * scaleX, y: 8.55 * scaleY),
            control1: CGPoint(x: 23.89 * scaleX, y: 8.49 * scaleY),
            control2: CGPoint(x: 25.26 * scaleX, y: 7.99 * scaleY)
        )
        path.addLine(to: CGPoint(x: 30.19 * scaleX, y: 10.07 * scaleY))
        path.addCurve(
            to: CGPoint(x: 31.44 * scaleX, y: 9.98 * scaleY),
            control1: CGPoint(x: 30.63 * scaleX, y: 10.26 * scaleY),
            control2: CGPoint(x: 31.06 * scaleX, y: 10.32 * scaleY)
        )
        path.addLine(to: CGPoint(x: 37.92 * scaleX, y: 4.11 * scaleY))
        path.addCurve(
            to: CGPoint(x: 38.97 * scaleX, y: 3.47 * scaleY),
            control1: CGPoint(x: 38.24 * scaleX, y: 3.82 * scaleY),
            control2: CGPoint(x: 38.59 * scaleX, y: 3.64 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 41.92 * scaleX, y: 3.53 * scaleY),
            control1: CGPoint(x: 39.92 * scaleX, y: 3.04 * scaleY),
            control2: CGPoint(x: 40.98 * scaleX, y: 3.07 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 43.85 * scaleX, y: 6.12 * scaleY),
            control1: CGPoint(x: 42.96 * scaleX, y: 4.04 * scaleY),
            control2: CGPoint(x: 43.67 * scaleX, y: 4.95 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 41.86 * scaleX, y: 9.99 * scaleY),
            control1: CGPoint(x: 44.08 * scaleX, y: 7.68 * scaleY),
            control2: CGPoint(x: 43.29 * scaleX, y: 9.25 * scaleY)
        )
        path.addLine(to: CGPoint(x: 33.22 * scaleX, y: 14.40 * scaleY))
        path.addCurve(
            to: CGPoint(x: 30.14 * scaleX, y: 14.56 * scaleY),
            control1: CGPoint(x: 32.27 * scaleX, y: 14.89 * scaleY),
            control2: CGPoint(x: 31.12 * scaleX, y: 15.02 * scaleY)
        )
        path.addLine(to: CGPoint(x: 26.78 * scaleX, y: 12.98 * scaleY))
        path.addCurve(
            to: CGPoint(x: 25.44 * scaleX, y: 13.34 * scaleY),
            control1: CGPoint(x: 26.25 * scaleX, y: 12.73 * scaleY),
            control2: CGPoint(x: 25.79 * scaleX, y: 12.90 * scaleY)
        )
        path.addLine(to: CGPoint(x: 12.87 * scaleX, y: 28.86 * scaleY))
        path.addLine(to: CGPoint(x: 9.36 * scaleX, y: 33.22 * scaleY))
        path.addCurve(
            to: CGPoint(x: 4.17 * scaleX, y: 35.37 * scaleY),
            control1: CGPoint(x: 8.10 * scaleX, y: 34.79 * scaleY),
            control2: CGPoint(x: 6.22 * scaleX, y: 35.67 * scaleY)
        )
        path.closeSubpath()
        
        // Path 2 - Top right element
        path.move(to: CGPoint(x: 22.57 * scaleX, y: 31.67 * scaleY))
        path.addCurve(
            to: CGPoint(x: 19.38 * scaleX, y: 29.20 * scaleY),
            control1: CGPoint(x: 21.16 * scaleX, y: 31.40 * scaleY),
            control2: CGPoint(x: 19.97 * scaleX, y: 30.47 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 21.77 * scaleX, y: 23.34 * scaleY),
            control1: CGPoint(x: 18.33 * scaleX, y: 26.90 * scaleY),
            control2: CGPoint(x: 19.49 * scaleX, y: 24.33 * scaleY)
        )
        path.addLine(to: CGPoint(x: 27.23 * scaleX, y: 20.95 * scaleY))
        path.addCurve(
            to: CGPoint(x: 27.68 * scaleX, y: 20.23 * scaleY),
            control1: CGPoint(x: 27.52 * scaleX, y: 20.82 * scaleY),
            control2: CGPoint(x: 27.67 * scaleX, y: 20.50 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 26.41 * scaleX, y: 17.73 * scaleY),
            control1: CGPoint(x: 27.72 * scaleX, y: 19.40 * scaleY),
            control2: CGPoint(x: 26.30 * scaleX, y: 19.27 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 27.46 * scaleX, y: 16.15 * scaleY),
            control1: CGPoint(x: 26.46 * scaleX, y: 17.09 * scaleY),
            control2: CGPoint(x: 26.85 * scaleX, y: 16.48 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 30.01 * scaleX, y: 16.51 * scaleY),
            control1: CGPoint(x: 28.30 * scaleX, y: 15.69 * scaleY),
            control2: CGPoint(x: 29.29 * scaleX, y: 15.89 * scaleY)
        )
        path.addLine(to: CGPoint(x: 33.42 * scaleX, y: 19.44 * scaleY))
        path.addCurve(
            to: CGPoint(x: 34.39 * scaleX, y: 22.44 * scaleY),
            control1: CGPoint(x: 34.28 * scaleX, y: 20.18 * scaleY),
            control2: CGPoint(x: 34.58 * scaleX, y: 21.34 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 33.15 * scaleX, y: 24.54 * scaleY),
            control1: CGPoint(x: 34.24 * scaleX, y: 23.29 * scaleY),
            control2: CGPoint(x: 33.77 * scaleX, y: 23.95 * scaleY)
        )
        path.addLine(to: CGPoint(x: 27.15 * scaleX, y: 30.20 * scaleY))
        path.addCurve(
            to: CGPoint(x: 22.57 * scaleX, y: 31.66 * scaleY),
            control1: CGPoint(x: 25.92 * scaleX, y: 31.36 * scaleY),
            control2: CGPoint(x: 24.31 * scaleX, y: 31.99 * scaleY)
        )
        path.closeSubpath()
        
        // Path 3 - Middle left element
        path.move(to: CGPoint(x: 11.11 * scaleX, y: 14.85 * scaleY))
        path.addCurve(
            to: CGPoint(x: 5.91 * scaleX, y: 13.08 * scaleY),
            control1: CGPoint(x: 9.14 * scaleX, y: 15.92 * scaleY),
            control2: CGPoint(x: 6.72 * scaleX, y: 15.05 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 6.41 * scaleX, y: 9.47 * scaleY),
            control1: CGPoint(x: 5.41 * scaleX, y: 11.82 * scaleY),
            control2: CGPoint(x: 5.61 * scaleX, y: 10.50 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 8.73 * scaleX, y: 8.04 * scaleY),
            control1: CGPoint(x: 6.99 * scaleX, y: 8.74 * scaleY),
            control2: CGPoint(x: 7.80 * scaleX, y: 8.23 * scaleY)
        )
        path.addLine(to: CGPoint(x: 19.64 * scaleX, y: 5.84 * scaleY))
        path.addCurve(
            to: CGPoint(x: 21.83 * scaleX, y: 6.81 * scaleY),
            control1: CGPoint(x: 20.52 * scaleX, y: 5.66 * scaleY),
            control2: CGPoint(x: 21.42 * scaleX, y: 6.04 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 20.93 * scaleX, y: 9.46 * scaleY),
            control1: CGPoint(x: 22.36 * scaleX, y: 7.82 * scaleY),
            control2: CGPoint(x: 21.89 * scaleX, y: 8.94 * scaleY)
        )
        path.addLine(to: CGPoint(x: 16.27 * scaleX, y: 12.04 * scaleY))
        path.addLine(to: CGPoint(x: 11.11 * scaleX, y: 14.84 * scaleY))
        path.closeSubpath()
        
        // Path 4 - Top circle/dot
        path.move(to: CGPoint(x: 32.29 * scaleX, y: 5.80 * scaleY))
        path.addCurve(
            to: CGPoint(x: 29.24 * scaleX, y: 7.74 * scaleY),
            control1: CGPoint(x: 31.63 * scaleX, y: 6.94 * scaleY),
            control2: CGPoint(x: 30.47 * scaleX, y: 7.63 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 25.82 * scaleX, y: 6.35 * scaleY),
            control1: CGPoint(x: 27.93 * scaleX, y: 7.86 * scaleY),
            control2: CGPoint(x: 26.66 * scaleX, y: 7.35 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 25.24 * scaleX, y: 2.41 * scaleY),
            control1: CGPoint(x: 24.90 * scaleX, y: 5.23 * scaleY),
            control2: CGPoint(x: 24.67 * scaleX, y: 3.74 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 30.95 * scaleX, y: 0.57 * scaleY),
            control1: CGPoint(x: 26.19 * scaleX, y: 0.19 * scaleY),
            control2: CGPoint(x: 28.89 * scaleX, y: -0.67 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 32.30 * scaleX, y: 5.80 * scaleY),
            control1: CGPoint(x: 32.77 * scaleX, y: 1.66 * scaleY),
            control2: CGPoint(x: 33.38 * scaleX, y: 3.94 * scaleY)
        )
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Stride Logo View
struct StrideLogoView: View {
    var height: CGFloat = 32
    var color: Color = .stridePrimary
    
    var body: some View {
        StrideLogoShape()
            .fill(color)
            .aspectRatio(44/36, contentMode: .fit)
            .frame(height: height)
    }
}

// MARK: - Time Icon View
struct TimeIconView: View {
    var size: CGFloat = 20
    
    var body: some View {
        Image("TimeIcon")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(.primary)
            .aspectRatio(20/22, contentMode: .fit)
            .frame(width: size, height: size * 22/20)
    }
}

// MARK: - Flag Icon View
struct FlagIconView: View {
    var size: CGFloat = 20
    var color: Color = .primary
    
    var body: some View {
        Image("FlagIcon")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(color)
            .aspectRatio(21/19, contentMode: .fit)
            .frame(width: size * 21/20, height: size * 19/20)
    }
}

// MARK: - Checkmark Circle View
struct CheckmarkCircleView: View {
    let isCompleted: Bool
    var size: CGFloat = 10
    
    private let incompleteColor = Color(hex: "F6F6F6")
    
    var body: some View {
        if isCompleted {
            Image("CheckmarkIcon")
                .resizable()
                .renderingMode(.original) // CheckmarkIcon is set to "original" in asset catalog
                .aspectRatio(1, contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(incompleteColor)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Treadmill Icon View
struct TreadmillIconView: View {
    var size: CGFloat = 18
    var color: Color = .primary
    
    var body: some View {
        Image("TreadmillIcon")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(color)
            .aspectRatio(18/19, contentMode: .fit)
            .frame(width: size, height: size * 19/18)
    }
}

// MARK: - Close Icon View
struct CloseIconView: View {
    var size: CGFloat = 12
    var color: Color = .primary
    
    var body: some View {
        Image("CloseIcon")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(color)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Heart Icon Shape (Rest Day)
struct HeartIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (16x14)
        let scaleX = w / 16
        let scaleY = h / 14
        
        path.move(to: CGPoint(x: 7.316 * scaleX, y: 12.6893 * scaleY))
        path.addCurve(
            to: CGPoint(x: 0.75 * scaleX, y: 4.51854 * scaleY),
            control1: CGPoint(x: 5.286 * scaleX, y: 12.0219 * scaleY),
            control2: CGPoint(x: 0.75 * scaleX, y: 9.23764 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 4.642 * scaleX, y: 0.75 * scaleY),
            control1: CGPoint(x: 0.75 * scaleX, y: 2.43539 * scaleY),
            control2: CGPoint(x: 2.493 * scaleX, y: 0.75 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 7.75 * scaleX, y: 2.26011 * scaleY),
            control1: CGPoint(x: 5.916 * scaleX, y: 0.75 * scaleY),
            control2: CGPoint(x: 7.043 * scaleX, y: 1.34326 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 10.858 * scaleX, y: 0.75 * scaleY),
            control1: CGPoint(x: 8.457 * scaleX, y: 1.34326 * scaleY),
            control2: CGPoint(x: 9.591 * scaleX, y: 0.75 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 14.75 * scaleX, y: 4.51854 * scaleY),
            control1: CGPoint(x: 13.007 * scaleX, y: 0.75 * scaleY),
            control2: CGPoint(x: 14.75 * scaleX, y: 2.43539 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 8.184 * scaleX, y: 12.6893 * scaleY),
            control1: CGPoint(x: 14.75 * scaleX, y: 9.23764 * scaleY),
            control2: CGPoint(x: 10.214 * scaleX, y: 12.0219 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 7.316 * scaleX, y: 12.6893 * scaleY),
            control1: CGPoint(x: 7.946 * scaleX, y: 12.7702 * scaleY),
            control2: CGPoint(x: 7.554 * scaleX, y: 12.7702 * scaleY)
        )
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Heart Icon View (Rest Day)
struct HeartIconView: View {
    var size: CGFloat = 16
    var color: Color = Color(hex: "8A0063")
    
    var body: some View {
        HeartIconShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .aspectRatio(16/14, contentMode: .fit)
            .frame(width: size, height: size * 14/16)
    }
}

// MARK: - Workout Icon Shape (Kettlebell)
struct WorkoutIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (14x17)
        let scaleX = w / 14
        let scaleY = h / 17
        
        // Handle path
        path.move(to: CGPoint(x: 10.3752 * scaleX, y: 5.875 * scaleY))
        path.addCurve(
            to: CGPoint(x: 11.3724 * scaleX, y: 2.17847 * scaleY),
            control1: CGPoint(x: 11.2838 * scaleX, y: 3.72914 * scaleY),
            control2: CGPoint(x: 11.7403 * scaleX, y: 2.98853 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 10.896 * scaleX, y: 1.5138 * scaleY),
            control1: CGPoint(x: 11.2597 * scaleX, y: 1.93036 * scaleY),
            control2: CGPoint(x: 11.098 * scaleX, y: 1.70479 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 2.35396 * scaleX, y: 1.5138 * scaleY),
            control1: CGPoint(x: 9.64253 * scaleX, y: 0.328732 * scaleY),
            control2: CGPoint(x: 3.60742 * scaleX, y: 0.328732 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 1.87759 * scaleX, y: 2.17847 * scaleY),
            control1: CGPoint(x: 2.15195 * scaleX, y: 1.70479 * scaleY),
            control2: CGPoint(x: 1.99029 * scaleX, y: 1.93036 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 2.87507 * scaleX, y: 5.875 * scaleY),
            control1: CGPoint(x: 1.50967 * scaleX, y: 2.98853 * scaleY),
            control2: CGPoint(x: 1.96644 * scaleX, y: 3.72914 * scaleY)
        )
        
        return path
    }
}

struct WorkoutIconBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (14x17)
        let scaleX = w / 14
        let scaleY = h / 17
        
        // Body path
        path.move(to: CGPoint(x: 6.625 * scaleX, y: 5.125 * scaleY))
        path.addCurve(
            to: CGPoint(x: 0.625 * scaleX, y: 11.125 * scaleY),
            control1: CGPoint(x: 3.31129 * scaleX, y: 5.125 * scaleY),
            control2: CGPoint(x: 0.625 * scaleX, y: 7.81129 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 1.88097 * scaleX, y: 14.7989 * scaleY),
            control1: CGPoint(x: 0.625 * scaleX, y: 12.5091 * scaleY),
            control2: CGPoint(x: 1.09367 * scaleX, y: 13.7838 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 3.79083 * scaleX, y: 15.625 * scaleY),
            control1: CGPoint(x: 2.42082 * scaleX, y: 15.495 * scaleY),
            control2: CGPoint(x: 2.92274 * scaleX, y: 15.625 * scaleY)
        )
        path.addLine(to: CGPoint(x: 9.45917 * scaleX, y: 15.625 * scaleY))
        path.addCurve(
            to: CGPoint(x: 11.369 * scaleX, y: 14.7989 * scaleY),
            control1: CGPoint(x: 10.3273 * scaleX, y: 15.625 * scaleY),
            control2: CGPoint(x: 10.8292 * scaleX, y: 15.495 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 12.625 * scaleX, y: 11.125 * scaleY),
            control1: CGPoint(x: 12.1563 * scaleX, y: 13.7838 * scaleY),
            control2: CGPoint(x: 12.625 * scaleX, y: 12.5091 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 6.625 * scaleX, y: 5.125 * scaleY),
            control1: CGPoint(x: 12.625 * scaleX, y: 7.81129 * scaleY),
            control2: CGPoint(x: 9.93871 * scaleX, y: 5.125 * scaleY)
        )
        path.closeSubpath()
        
        return path
    }
}

struct WorkoutIconCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (14x17)
        let scaleX = w / 14
        let scaleY = h / 17
        
        // Inner circle
        let centerX = 6.625 * scaleX
        let centerY = 11.625 * scaleY
        let radius = 2 * scaleX
        
        path.addEllipse(in: CGRect(
            x: centerX - radius,
            y: centerY - radius * scaleY / scaleX,
            width: radius * 2,
            height: radius * 2 * scaleY / scaleX
        ))
        
        return path
    }
}

// MARK: - Workout Icon View (Kettlebell)
struct WorkoutIconView: View {
    var size: CGFloat = 14
    var color: Color = Color(hex: "CF0000")
    
    var body: some View {
        ZStack {
            WorkoutIconShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            WorkoutIconBodyShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
            WorkoutIconCircleShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))
        }
        .aspectRatio(14/17, contentMode: .fit)
        .frame(width: size, height: size * 17/14)
    }
}

// MARK: - Settings Icon Shape
struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (25x24)
        let scaleX = w / 25
        let scaleY = h / 24
        
        // Center circle (knob)
        let centerX = 12.4928 * scaleX
        let centerY = 11.8468 * scaleY
        let radius = 3.44784 * scaleX // Approximate radius from the path
        
        path.addEllipse(in: CGRect(
            x: centerX - radius,
            y: centerY - radius,
            width: radius * 2,
            height: radius * 2
        ))
        
        // Gear outer shape
        path.move(to: CGPoint(x: 1 * scaleX, y: 10.8273 * scaleY))
        path.addCurve(
            to: CGPoint(x: 3.16846 * scaleX, y: 8.65887 * scaleY),
            control1: CGPoint(x: 1.97581 * scaleX, y: 8.65887 * scaleY),
            control2: CGPoint(x: 1.97581 * scaleX, y: 8.65887 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 5.05502 * scaleX, y: 5.3845 * scaleY),
            control1: CGPoint(x: 6.09836 * scaleX, y: 7.18289 * scaleY),
            control2: CGPoint(x: 5.25018 * scaleX, y: 8.65887 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 5.85735 * scaleX, y: 2.41371 * scaleY),
            control1: CGPoint(x: 4.45033 * scaleX, y: 4.3422 * scaleY),
            control2: CGPoint(x: 4.81649 * scaleX, y: 2.99919 * scaleY)
        )
        path.addLine(to: CGPoint(x: 7.83065 * scaleX, y: 1.26443 * scaleY))
        path.addCurve(
            to: CGPoint(x: 10.4545 * scaleX, y: 1.95833 * scaleY),
            control1: CGPoint(x: 8.7414 * scaleX, y: 0.722312 * scaleY),
            control2: CGPoint(x: 9.91237 * scaleX, y: 1.04758 * scaleY)
        )
        path.addLine(to: CGPoint(x: 10.5846 * scaleX, y: 2.17518 * scaleY))
        path.addCurve(
            to: CGPoint(x: 11.6255 * scaleX, y: 3.975 * scaleY),
            control1: CGPoint(x: 11.6255 * scaleX, y: 3.975 * scaleY),
            control2: CGPoint(x: 13.3168 * scaleX, y: 3.975 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 14.3577 * scaleX, y: 2.17518 * scaleY),
            control1: CGPoint(x: 13.3168 * scaleX, y: 3.975 * scaleY),
            control2: CGPoint(x: 14.3577 * scaleX, y: 2.17518 * scaleY)
        )
        path.addLine(to: CGPoint(x: 14.4878 * scaleX, y: 1.95833 * scaleY))
        path.addCurve(
            to: CGPoint(x: 17.1117 * scaleX, y: 1.26443 * scaleY),
            control1: CGPoint(x: 15.0299 * scaleX, y: 1.04758 * scaleY),
            control2: CGPoint(x: 16.2009 * scaleX, y: 0.743997 * scaleY)
        )
        path.addLine(to: CGPoint(x: 19.085 * scaleX, y: 2.41371 * scaleY))
        path.addCurve(
            to: CGPoint(x: 19.8873 * scaleX, y: 5.3845 * scaleY),
            control1: CGPoint(x: 20.1258 * scaleX, y: 3.02088 * scaleY),
            control2: CGPoint(x: 20.4945 * scaleX, y: 4.34364 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 21.7738 * scaleX, y: 8.65887 * scaleY),
            control1: CGPoint(x: 18.8464 * scaleX, y: 7.18432 * scaleY),
            control2: CGPoint(x: 19.6921 * scaleX, y: 8.65887 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 23.9423 * scaleX, y: 10.8273 * scaleY),
            control1: CGPoint(x: 22.9665 * scaleX, y: 8.65887 * scaleY),
            control2: CGPoint(x: 22.9665 * scaleX, y: 9.63468 * scaleY)
        )
        path.addLine(to: CGPoint(x: 23.9423 * scaleX, y: 12.844 * scaleY))
        path.addCurve(
            to: CGPoint(x: 21.7738 * scaleX, y: 15.0125 * scaleY),
            control1: CGPoint(x: 22.9665 * scaleX, y: 15.0125 * scaleY),
            control2: CGPoint(x: 22.9665 * scaleX, y: 14.0366 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 19.8873 * scaleX, y: 18.2868 * scaleY),
            control1: CGPoint(x: 19.6921 * scaleX, y: 15.0125 * scaleY),
            control2: CGPoint(x: 18.8464 * scaleX, y: 16.487 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 19.085 * scaleX, y: 21.2576 * scaleY),
            control1: CGPoint(x: 20.4945 * scaleX, y: 19.3277 * scaleY),
            control2: CGPoint(x: 20.1258 * scaleX, y: 20.6721 * scaleY)
        )
        path.addLine(to: CGPoint(x: 17.1117 * scaleX, y: 22.4069 * scaleY))
        path.addCurve(
            to: CGPoint(x: 14.4878 * scaleX, y: 21.713 * scaleY),
            control1: CGPoint(x: 16.2009 * scaleX, y: 22.949 * scaleY),
            control2: CGPoint(x: 15.0299 * scaleX, y: 22.6237 * scaleY)
        )
        path.addLine(to: CGPoint(x: 14.3577 * scaleX, y: 21.4962 * scaleY))
        path.addCurve(
            to: CGPoint(x: 10.5846 * scaleX, y: 21.4962 * scaleY),
            control1: CGPoint(x: 13.3168 * scaleX, y: 19.6963 * scaleY),
            control2: CGPoint(x: 11.6255 * scaleX, y: 19.6963 * scaleY)
        )
        path.addLine(to: CGPoint(x: 10.4545 * scaleX, y: 21.713 * scaleY))
        path.addCurve(
            to: CGPoint(x: 7.83065 * scaleX, y: 22.4069 * scaleY),
            control1: CGPoint(x: 9.91237 * scaleX, y: 22.6237 * scaleY),
            control2: CGPoint(x: 8.7414 * scaleX, y: 22.9273 * scaleY)
        )
        path.addLine(to: CGPoint(x: 5.85735 * scaleX, y: 21.2576 * scaleY))
        path.addCurve(
            to: CGPoint(x: 5.05502 * scaleX, y: 18.2868 * scaleY),
            control1: CGPoint(x: 4.81649 * scaleX, y: 20.6505 * scaleY),
            control2: CGPoint(x: 4.44785 * scaleX, y: 19.3277 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 3.16846 * scaleX, y: 15.0125 * scaleY),
            control1: CGPoint(x: 6.09588 * scaleX, y: 16.487 * scaleY),
            control2: CGPoint(x: 5.25018 * scaleX, y: 15.0125 * scaleY)
        )
        path.addCurve(
            to: CGPoint(x: 1 * scaleX, y: 12.844 * scaleY),
            control1: CGPoint(x: 1.97581 * scaleX, y: 15.0341 * scaleY),
            control2: CGPoint(x: 1.97581 * scaleX, y: 14.0583 * scaleY)
        )
        path.addLine(to: CGPoint(x: 1 * scaleX, y: 10.8273 * scaleY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Settings Icon View
struct SettingsIconView: View {
    var size: CGFloat = 24
    var color: Color = .primary
    
    var body: some View {
        ZStack {
            SettingsIconShape()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(25/24, contentMode: .fit)
        .frame(width: size, height: size * 24/25)
    }
}

// MARK: - Stats Icon Shape
struct StatsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors based on original viewBox (30x23)
        let scaleX = w / 30
        let scaleY = h / 23
        
        // Bottom chart shape
        path.move(to: CGPoint(x: 1.00015 * scaleX, y: 16.2575 * scaleY))
        path.addLine(to: CGPoint(x: 1.00015 * scaleX, y: 12.1944 * scaleY))
        path.addCurve(
            to: CGPoint(x: 1.48169 * scaleX, y: 11.3393 * scaleY),
            control1: CGPoint(x: 1.00015 * scaleX, y: 11.8448 * scaleY),
            control2: CGPoint(x: 1.18274 * scaleX, y: 11.5205 * scaleY)
        )
        path.addLine(to: CGPoint(x: 9.53703 * scaleX, y: 6.45523 * scaleY))
        path.addCurve(
            to: CGPoint(x: 10.5555 * scaleX, y: 6.44431 * scaleY),
            control1: CGPoint(x: 9.84909 * scaleX, y: 6.26602 * scaleY),
            control2: CGPoint(x: 10.2394 * scaleX, y: 6.26184 * scaleY)
        )
        path.addLine(to: CGPoint(x: 19.0395 * scaleX, y: 11.3426 * scaleY))
        path.addCurve(
            to: CGPoint(x: 20.0395 * scaleX, y: 11.3426 * scaleY),
            control1: CGPoint(x: 19.3489 * scaleX, y: 11.5212 * scaleY),
            control2: CGPoint(x: 19.7301 * scaleX, y: 11.5212 * scaleY)
        )
        path.addLine(to: CGPoint(x: 25.1288 * scaleX, y: 8.40431 * scaleY))
        path.addCurve(
            to: CGPoint(x: 28.1288 * scaleX, y: 10.1364 * scaleY),
            control1: CGPoint(x: 26.4621 * scaleX, y: 7.63451 * scaleY),
            control2: CGPoint(x: 28.1288 * scaleX, y: 8.59676 * scaleY)
        )
        path.addLine(to: CGPoint(x: 28.1288 * scaleX, y: 16.2575 * scaleY))
        path.addCurve(
            to: CGPoint(x: 23.1288 * scaleX, y: 21.2575 * scaleY),
            control1: CGPoint(x: 28.1288 * scaleX, y: 19.019 * scaleY),
            control2: CGPoint(x: 25.8902 * scaleX, y: 21.2575 * scaleY)
        )
        path.addLine(to: CGPoint(x: 6.00015 * scaleX, y: 21.2575 * scaleY))
        path.addCurve(
            to: CGPoint(x: 1.00015 * scaleX, y: 16.2575 * scaleY),
            control1: CGPoint(x: 3.23873 * scaleX, y: 21.2575 * scaleY),
            control2: CGPoint(x: 1.00015 * scaleX, y: 19.019 * scaleY)
        )
        path.closeSubpath()
        
        // Top chart shape
        path.move(to: CGPoint(x: 1.00015 * scaleX, y: 6.32095 * scaleY))
        path.addLine(to: CGPoint(x: 9.53703 * scaleX, y: 1.14493 * scaleY))
        path.addCurve(
            to: CGPoint(x: 10.5555 * scaleX, y: 1.134 * scaleY),
            control1: CGPoint(x: 9.84909 * scaleX, y: 0.955721 * scaleY),
            control2: CGPoint(x: 10.2394 * scaleX, y: 0.951534 * scaleY)
        )
        path.addLine(to: CGPoint(x: 19.0395 * scaleX, y: 6.03228 * scaleY))
        path.addCurve(
            to: CGPoint(x: 20.0395 * scaleX, y: 6.03228 * scaleY),
            control1: CGPoint(x: 19.3489 * scaleX, y: 6.21091 * scaleY),
            control2: CGPoint(x: 19.7301 * scaleX, y: 6.21091 * scaleY)
        )
        path.addLine(to: CGPoint(x: 28.1288 * scaleX, y: 1.36196 * scaleY))
        
        return path
    }
}

// MARK: - Stats Icon View
struct StatsIconView: View {
    var size: CGFloat = 24
    var color: Color = .primary
    
    var body: some View {
        StatsIconShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .aspectRatio(30/23, contentMode: .fit)
            .frame(width: size, height: size * 23/30)
    }
}

// MARK: - Run Icon Shape (Simple runner figure)
struct RunIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors - using a 24x24 viewBox
        let scaleX = w / 24
        let scaleY = h / 24
        
        // Head (circle)
        let headCenterX = 12 * scaleX
        let headCenterY = 4 * scaleY
        let headRadius = 2.5 * scaleX
        path.addEllipse(in: CGRect(
            x: headCenterX - headRadius,
            y: headCenterY - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        
        // Body (torso)
        path.move(to: CGPoint(x: 12 * scaleX, y: 6.5 * scaleY))
        path.addLine(to: CGPoint(x: 12 * scaleX, y: 14 * scaleY))
        
        // Arms (running motion)
        // Left arm (forward)
        path.move(to: CGPoint(x: 12 * scaleX, y: 8 * scaleY))
        path.addLine(to: CGPoint(x: 8 * scaleX, y: 6 * scaleY))
        // Right arm (back)
        path.move(to: CGPoint(x: 12 * scaleX, y: 8 * scaleY))
        path.addLine(to: CGPoint(x: 16 * scaleX, y: 10 * scaleY))
        
        // Legs (running motion)
        // Left leg (forward)
        path.move(to: CGPoint(x: 12 * scaleX, y: 14 * scaleY))
        path.addLine(to: CGPoint(x: 9 * scaleX, y: 20 * scaleY))
        // Right leg (back)
        path.move(to: CGPoint(x: 12 * scaleX, y: 14 * scaleY))
        path.addLine(to: CGPoint(x: 15 * scaleX, y: 20 * scaleY))
        
        return path
    }
}

// MARK: - Run Icon View
struct RunIconView: View {
    var size: CGFloat = 24
    var color: Color = .primary
    
    var body: some View {
        RunIconShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Plan Icon Shape (Clipboard with folded corner)
struct PlanIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Scale factors - using a 24x24 viewBox
        let scaleX = w / 24
        let scaleY = h / 24
        
        // Main clipboard body
        path.move(to: CGPoint(x: 6 * scaleX, y: 3 * scaleY))
        path.addLine(to: CGPoint(x: 18 * scaleX, y: 3 * scaleY))
        path.addLine(to: CGPoint(x: 18 * scaleX, y: 21 * scaleY))
        path.addLine(to: CGPoint(x: 6 * scaleX, y: 21 * scaleY))
        path.closeSubpath()
        
        // Folded corner
        path.move(to: CGPoint(x: 18 * scaleX, y: 3 * scaleY))
        path.addLine(to: CGPoint(x: 18 * scaleX, y: 8 * scaleY))
        path.addLine(to: CGPoint(x: 13 * scaleX, y: 3 * scaleY))
        path.closeSubpath()
        
        // Top clip
        path.move(to: CGPoint(x: 9 * scaleX, y: 3 * scaleY))
        path.addLine(to: CGPoint(x: 9 * scaleX, y: 1 * scaleY))
        path.addCurve(
            to: CGPoint(x: 15 * scaleX, y: 1 * scaleY),
            control1: CGPoint(x: 11 * scaleX, y: 1 * scaleY),
            control2: CGPoint(x: 13 * scaleX, y: 1 * scaleY)
        )
        path.addLine(to: CGPoint(x: 15 * scaleX, y: 3 * scaleY))
        
        // Lines on clipboard (representing text)
        path.move(to: CGPoint(x: 8 * scaleX, y: 7 * scaleY))
        path.addLine(to: CGPoint(x: 16 * scaleX, y: 7 * scaleY))
        
        path.move(to: CGPoint(x: 8 * scaleX, y: 10 * scaleY))
        path.addLine(to: CGPoint(x: 16 * scaleX, y: 10 * scaleY))
        
        path.move(to: CGPoint(x: 8 * scaleX, y: 13 * scaleY))
        path.addLine(to: CGPoint(x: 14 * scaleX, y: 13 * scaleY))
        
        return path
    }
}

// MARK: - Plan Icon View
struct PlanIconView: View {
    var size: CGFloat = 24
    var color: Color = .primary
    
    var body: some View {
        PlanIconShape()
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 30) {
        StrideLogoView(height: 40)
        
        HStack(spacing: 20) {
            TimeIconView()
            FlagIconView()
        }
        
        HStack(spacing: 20) {
            CheckmarkCircleView(isCompleted: true, size: 20)
            CheckmarkCircleView(isCompleted: false, size: 20)
        }
        
        HStack(spacing: 20) {
            TreadmillIconView(size: 24)
            CloseIconView(size: 16)
        }
        
        HStack(spacing: 20) {
            HeartIconView(size: 24)
            WorkoutIconView(size: 20)
        }
    }
    .padding()
}
