import SwiftUI

/// Shared visual language for the redesigned Stats and Profile tabs.
struct StridePageStyle {
    let appearance: RunLobbyAppearance
    var ink: Color { appearance.foreground }
    var muted: Color { appearance.secondary }
    var accent: Color { appearance == .red ? .white : .stridePrimary }
    var card: Color {
        switch appearance {
        case .black: return .white.opacity(0.055)
        case .white: return Color(white: 0.95)
        case .red: return .white.opacity(0.14)
        }
    }
    var rule: Color { ink.opacity(appearance == .white ? 0.12 : 0.20) }
}

extension View {
    /// Shared surface for secondary flows reached from the main tabs.
    func strideSecondaryScreen() -> some View {
        modifier(StrideSecondaryScreenModifier())
    }

    func stridePageCard(_ style: StridePageStyle, radius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(style.card, in: shape)
            .overlay(shape.stroke(
                LinearGradient(
                    colors: [style.appearance == .white ? .white : .white.opacity(0.48), style.ink.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 0.7
            ))
    }
}

private struct StrideSecondaryScreenModifier: ViewModifier {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    func body(content: Content) -> some View {
        content
            .font(.inter(size: 15))
            .tint(appearance == .red ? .white : .stridePrimary)
            .scrollContentBackground(.hidden)
            .background { StridePageBackdrop().ignoresSafeArea() }
            .preferredColorScheme(appearance.colorScheme)
    }
}

struct StrideSecondaryCard: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var style: StridePageStyle {
        .init(appearance: RunLobbyAppearance(rawValue: appearanceRaw) ?? .black)
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(style.card)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.45), style.ink.opacity(0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
            }
    }
}

struct StridePageBackdrop: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    var body: some View {
        if appearance == .red {
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.65, green: 0.055, blue: 0.045)
                    Ellipse().fill(Color.red.opacity(0.28))
                        .frame(width: geometry.size.width, height: 240)
                        .blur(radius: 70).offset(x: 100, y: -100)
                    Canvas { context, size in
                        var dots = Path()
                        for x in stride(from: 0.0, to: size.width, by: 5) {
                            for y in stride(from: 0.0, to: size.height, by: 5) {
                                dots.addEllipse(in: CGRect(x: x, y: y, width: 0.7, height: 0.7))
                            }
                        }
                        context.fill(dots, with: .color(.white.opacity(0.12)))
                    }
                }
            }
            .allowsHitTesting(false)
        } else {
            PlanPageBackdrop()
        }
    }
}

struct StridePageHeader: View {
    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @ObservedObject private var auth = AuthService.shared
    var profileAction: () -> Void
    var redUsesDarkLogo = false
    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }
    private var initials: String {
        let name: String
        switch auth.authState {
        case .signedIn(let user), .needsProfile(let user): name = user.name ?? user.displayName ?? ""
        default: name = ""
        }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "BC" : letters.uppercased()
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(appearance == .white ? "StrideLogo" : (appearance == .red && !redUsesDarkLogo ? "StrideLogoRed" : "StrideLogoDark"))
                .resizable().aspectRatio(690.0 / 156.0, contentMode: .fit)
                .frame(width: 120).accessibilityLabel("Stride")
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.25)) { appearanceRaw = appearance.next.rawValue } } label: {
                Image(systemName: appearance.icon).font(.system(size: 16, weight: .light))
                    .foregroundStyle(appearance == .red ? .white : style.ink)
                    .frame(width: 40, height: 40)
                    .background {
                        if appearance == .red { Circle().fill(Color.stridePrimary) }
                        else { Circle().fill(.ultraThinMaterial) }
                    }
                    .overlay(Circle().stroke(style.rule, lineWidth: 0.5))
            }
            .accessibilityLabel("Appearance: \(appearance.rawValue). Switch to \(appearance.next.rawValue)")
            .accessibilityIdentifier("runAppearanceToggle")
            Button(action: profileAction) {
                Text(initials).font(.runEyebrow(10))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(style.rule, lineWidth: 0.5))
            }
            .accessibilityLabel("Profile")
        }
        .buttonStyle(.plain)
        .foregroundStyle(style.ink)
    }
}

struct StrideSectionHeading: View {
    let title: String
    var trailing: String? = nil
    let style: StridePageStyle
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.barlowCondensed(size: 23))
            Spacer()
            if let trailing {
                Text(trailing).font(.runEyebrow(9)).foregroundStyle(style.muted)
            }
        }
        .foregroundStyle(style.ink)
    }
}

private enum StatsPeriod: String, CaseIterable {
    case week = "WEEK", month = "MONTH", year = "YEAR"
    var component: Calendar.Component {
        switch self { case .week: return .weekOfYear; case .month: return .month; case .year: return .year }
    }
}

private struct StatsBucket: Identifiable {
    let id: Int
    let label: String
    let distance: Double
}

struct StatsDesignedPage: View {
    let runLogs: [RunLog]
    let plan: TrainingPlan?
    let shoes: [Shoe]
    var onSelectRun: (RunLog) -> Void
    var onOpenProfile: () -> Void

    @AppStorage(RunLobbyAppearance.storageKey) private var appearanceRaw = RunLobbyAppearance.black.rawValue
    @State private var selectedPeriod: StatsPeriod = .month
    @State private var showAllRuns = false

    private var appearance: RunLobbyAppearance { RunLobbyAppearance(rawValue: appearanceRaw) ?? .black }
    private var style: StridePageStyle { .init(appearance: appearance) }
    private var calendar: Calendar { Calendar.current }
    private var interval: DateInterval {
        calendar.dateInterval(of: selectedPeriod.component, for: Date()) ?? DateInterval(start: Date(), duration: 1)
    }
    private var periodLogs: [RunLog] {
        runLogs.filter { $0.completedAt >= interval.start && $0.completedAt < interval.end }
    }
    private var previousDistance: Double {
        guard let previous = calendar.date(byAdding: selectedPeriod.component, value: -1, to: interval.start),
              let range = calendar.dateInterval(of: selectedPeriod.component, for: previous) else { return 0 }
        return runLogs.filter { $0.completedAt >= range.start && $0.completedAt < range.end }
            .reduce(0) { $0 + $1.distanceKm }
    }
    private var periodTitle: String {
        switch selectedPeriod {
        case .week: return "THIS WEEK / TOTAL DISTANCE"
        case .month: return Date().formatted(.dateTime.month(.wide)).uppercased() + " / TOTAL DISTANCE"
        case .year: return "\(calendar.component(.year, from: Date())) / TOTAL DISTANCE"
        }
    }
    private var buckets: [StatsBucket] {
        let starts: [Date]
        let component: Calendar.Component
        switch selectedPeriod {
        case .week:
            starts = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
            component = .day
        case .month:
            starts = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0 * 7, to: interval.start) }
                .filter { $0 < interval.end }
            component = .day
        case .year:
            starts = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: interval.start) }
            component = .month
        }
        return starts.enumerated().map { index, start in
            let end = selectedPeriod == .month
                ? min(interval.end, calendar.date(byAdding: .day, value: 7, to: start) ?? interval.end)
                : (calendar.date(byAdding: component, value: 1, to: start) ?? interval.end)
            let distance = runLogs.filter { $0.completedAt >= start && $0.completedAt < end }
                .reduce(0) { $0 + $1.distanceKm }
            let label = selectedPeriod == .week ? start.formatted(.dateTime.weekday(.narrow))
                : selectedPeriod == .month ? "W\(index + 1)" : start.formatted(.dateTime.month(.abbreviated))
            return StatsBucket(id: index, label: label, distance: distance)
        }
    }
    private var easyRuns: [RunLog] {
        runLogs.filter { $0.plannedWorkoutType == .easyRun || $0.plannedWorkoutType == .recovery }
    }
    private var easyPace: Double? {
        let recent = Array(easyRuns.prefix(5))
        guard !recent.isEmpty else { return nil }
        return recent.map(\.avgPaceSecPerKm).reduce(0, +) / Double(recent.count)
    }
    private var easyPaceChange: Double? {
        let recent = Array(easyRuns.prefix(5)), previous = Array(easyRuns.dropFirst(5).prefix(5))
        guard !recent.isEmpty, !previous.isEmpty else { return nil }
        let previousTotal = previous.reduce(0.0) { $0 + $1.avgPaceSecPerKm }
        let recentTotal = recent.reduce(0.0) { $0 + $1.avgPaceSecPerKm }
        return previousTotal / Double(previous.count) - recentTotal / Double(recent.count)
    }
    private var longestRun: Double { runLogs.map(\.distanceKm).max() ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StridePageHeader(profileAction: onOpenProfile)
                    .padding(.bottom, 24)
                Text("YOUR TRAINING / IN NUMBERS")
                    .font(.runEyebrow(10)).tracking(1.3).foregroundStyle(style.muted)
                Text("THE WORK ADDS UP.")
                    .font(.barlowCondensed(size: 43))
                    .foregroundStyle(style.ink)
                    .minimumScaleFactor(0.75).lineLimit(1)
                    .padding(.top, 6)
                Text("A clear view of how your running is evolving.")
                    .font(.inter(size: 12)).foregroundStyle(style.muted)
                    .padding(.top, 3)
                volumeSection.padding(.top, 22)
                formSection.padding(.top, 25)
                recentRunsSection.padding(.top, 25)
                shoesSection.padding(.top, 25)
                milestonesSection.padding(.top, 25)
                deeperInsights.padding(.top, 25)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(style.ink)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StrideSectionHeading(title: "VOLUME", style: style)
                Spacer()
                ForEach(StatsPeriod.allCases, id: \.self) { period in
                    Button { selectedPeriod = period } label: {
                        Text(period.rawValue).font(.runEyebrow(9))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .foregroundStyle(style.ink)
                            .background(period == selectedPeriod ? style.ink.opacity(0.14) : .clear, in: Capsule())
                            .overlay(Capsule().stroke(style.rule, lineWidth: 0.5))
                    }.buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(periodTitle).font(.runEyebrow(9)).tracking(1).foregroundStyle(style.muted)
                HStack(alignment: .bottom, spacing: 0) {
                    volumeMetric(String(format: "%.0f", periodLogs.reduce(0) { $0 + $1.distanceKm }), unit: "KM", label: nil, large: true)
                    Rectangle().fill(style.rule).frame(width: 0.5, height: 36).padding(.horizontal, 13)
                    volumeMetric("\(periodLogs.count)", unit: nil, label: "RUNS")
                    Rectangle().fill(style.rule).frame(width: 0.5, height: 36).padding(.horizontal, 13)
                    volumeMetric(String(format: "%.0f", periodLogs.reduce(0) { $0 + $1.durationSeconds } / 3600), unit: nil, label: "HOURS")
                }
                let maxDistance = max(1, buckets.map(\.distance).max() ?? 1)
                HStack(alignment: .bottom, spacing: 7) {
                    ForEach(buckets) { bucket in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(bucket.distance > 0 ? style.accent : style.ink.opacity(0.10))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(3, 86 * bucket.distance / maxDistance))
                            Text(bucket.label).font(.runEyebrow(8)).foregroundStyle(style.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 106)
                HStack(spacing: 6) {
                    Circle().fill(style.accent).frame(width: 5, height: 5)
                    Text("COMPLETED").font(.runEyebrow(9)).foregroundStyle(style.muted)
                    Spacer()
                    let difference = periodLogs.reduce(0) { $0 + $1.distanceKm } - previousDistance
                    if previousDistance > 0 {
                        Text(String(format: "%+.0f%% VS PREVIOUS", difference / previousDistance * 100))
                            .font(.runEyebrow(9)).foregroundStyle(style.muted)
                    }
                }
            }
            .padding(15)
            .stridePageCard(style)
        }
    }

    private func volumeMetric(_ value: String, unit: String?, label: String?, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.barlowCondensed(size: large ? 47 : 29)).lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.runEyebrow(9)).foregroundStyle(style.muted) }
            }
            if let label { Text(label).font(.runEyebrow(8)).foregroundStyle(style.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            StrideSectionHeading(title: "FORM", trailing: "LAST 8 WEEKS", style: style)
            HStack(spacing: 9) {
                formCard(title: "EASY PACE", value: easyPace.map(paceText) ?? "—", unit: "/KM",
                         detail: easyPaceChange.map { abs($0) < 0.5 ? "PACE HOLDING STEADY" : String(format: "%+.0f SEC /KM VS PRIOR 5", -$0) } ?? "BUILDING A BASELINE",
                         values: Array(easyRuns.prefix(8).reversed().map(\.avgPaceSecPerKm)), reverse: true)
                let weeklyLongest = (0..<8).reversed().map { weeksAgo -> Double in
                    guard let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()),
                          let range = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
                    return runLogs.filter { $0.completedAt >= range.start && $0.completedAt < range.end }
                        .map(\.distanceKm).max() ?? 0
                }
                formCard(title: "LONGEST RUN", value: longestRun > 0 ? String(format: "%.0f", longestRun) : "—", unit: "KM",
                         detail: longestRun > 0 ? "PERSONAL DISTANCE BEST" : "NO RUNS YET",
                         values: weeklyLongest.filter { $0 > 0 }, reverse: false)
            }
        }
    }

    private func formCard(title: String, value: String, unit: String, detail: String,
                          values: [Double], reverse: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.runEyebrow(9)).foregroundStyle(style.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.barlowCondensed(size: 32)).lineLimit(1)
                Text(unit).font(.runEyebrow(9)).foregroundStyle(style.muted)
            }
            StatsSparkline(values: values, reverse: reverse, color: style.accent)
                .frame(height: 38)
            Text(detail).font(.runEyebrow(8)).foregroundStyle(style.muted)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .stridePageCard(style)
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showAllRuns.toggle() } label: {
                StrideSectionHeading(title: "RECENT RUNS", trailing: showAllRuns ? "SHOW LESS ↑" : "VIEW ALL ↗", style: style)
            }.buttonStyle(.plain)
            VStack(spacing: 0) {
                if runLogs.isEmpty {
                    Text("Your completed runs will appear here.")
                        .font(.inter(size: 12)).foregroundStyle(style.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(Array(runLogs.prefix(showAllRuns ? 30 : 3)), id: \.id) { run in
                    Button { onSelectRun(run) } label: {
                        HStack(spacing: 12) {
                            Rectangle().fill(style.accent).frame(width: 3, height: 39)
                            Image(systemName: run.dataSource == "gps" ? "location.north.line.fill" : "figure.run")
                                .font(.system(size: 13)).foregroundStyle(style.accent)
                                .frame(width: 30, height: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.effectiveTitle.uppercased()).font(.barlowCondensed(size: 22)).lineLimit(1)
                                Text("\(run.completedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()) · \(run.dataSource == "gps" ? "OUTDOOR" : "INDOOR")")
                                    .font(.inter(size: 10)).foregroundStyle(style.muted)
                            }
                            Spacer(minLength: 4)
                            Text(run.distanceDisplay.uppercased()).font(.barlowCondensed(size: 19))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(style.accent)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if run.id != runLogs.prefix(showAllRuns ? 30 : 3).last?.id {
                        Rectangle().fill(style.rule).frame(height: 0.5).padding(.leading, 54)
                    }
                }
            }
            .stridePageCard(style)
        }
    }

    private var shoesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { ShoesView().toolbar(.visible, for: .navigationBar) } label: {
                StrideSectionHeading(title: "YOUR SHOES", trailing: "MANAGE ↗", style: style)
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.ink)
            if shoes.isEmpty {
                NavigationLink { ShoesView().toolbar(.visible, for: .navigationBar) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shoeprints.fill").foregroundStyle(style.accent)
                        Text("ADD SHOES TO TRACK THEIR LIFESPAN")
                            .font(.runEyebrow(10)).foregroundStyle(style.muted)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(style.accent)
                    }
                    .padding(18)
                    .stridePageCard(style)
                    .foregroundStyle(style.ink)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(shoes, id: \.id) { shoe in
                    NavigationLink { ShoesView().toolbar(.visible, for: .navigationBar) } label: {
                        shoeCard(shoe)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(style.ink)
                }
            }
        }
    }

    private func shoeCard(_ shoe: Shoe) -> some View {
        let completed = min(42, max(0, Int((shoe.lifeFraction * 42).rounded(.down))))
        let remaining = max(0, shoe.effectiveMaxKm - shoe.totalDistanceKm)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                if shoe.photoData != nil || shoe.photoURL != nil {
                    ShoePhotoView(shoe: shoe, size: 38)
                } else {
                    Image("MilestoneFastest5K").resizable().scaledToFit()
                        .frame(width: 38, height: 38).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(shoe.name.uppercased()).font(.barlowCondensed(size: 25))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("\(shoe.usage.displayName.uppercased()) / \(shoe.isDefault ? "PRIMARY PAIR" : "ROTATION")")
                        .font(.runEyebrow(8)).foregroundStyle(style.muted)
                }
                Spacer(minLength: 3)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", shoe.totalDistanceKm)).font(.barlowCondensed(size: 35))
                Text(String(format: "/ %.0f KM", shoe.effectiveMaxKm))
                    .font(.barlowCondensed(size: 23)).foregroundStyle(style.muted)
                Spacer()
                Text(shoe.lifeFraction >= 1 ? "REPLACE SOON" : String(format: "%.0f KM LEFT", remaining))
                    .font(.runEyebrow(9)).foregroundStyle(shoe.lifeFraction >= 1 ? style.accent : style.muted)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<42, id: \.self) { index in
                    let wave = 0.3 + 0.7 * abs(sin(Double(index) * 0.30))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index < completed ? style.accent : style.ink.opacity(0.18))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5 + 15 * wave)
                }
            }
            .frame(height: 21, alignment: .bottom)
            HStack {
                Text("WORN").font(.runEyebrow(8)).foregroundStyle(style.muted)
                Spacer()
                Text("RECOMMENDED LIFESPAN").font(.runEyebrow(8)).foregroundStyle(style.muted)
            }
        }
        .padding(16)
        .stridePageCard(style)
        .foregroundStyle(style.ink)
        .accessibilityElement(children: .combine)
    }

    private var milestonesSection: some View {
        let rows: [(String, String, String)] = [
            ("FASTEST 5K", StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 5)?.timeString ?? "—", "MilestoneFastest5K"),
            ("FASTEST 10K", StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 10)?.timeString ?? "—", "MilestoneFastest10K"),
            ("FASTEST 21K", StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 21)?.timeString ?? "—", "MilestoneFastest21K"),
            ("FASTEST 42K", StatsViewModel.fastestConsecutiveTime(from: runLogs, distanceKm: 42)?.timeString ?? "—", "MilestoneFastest42K"),
            ("LONGEST RUN", longestRun > 0 ? String(format: "%.1f KM", longestRun) : "—", "MilestoneLongestRun"),
            ("BEST WEEK", StatsViewModel.highestWeeklyMileage(from: runLogs) > 0
                ? String(format: "%.0f KM", StatsViewModel.highestWeeklyMileage(from: runLogs)) : "—", "MilestoneBestWeek")
        ]
        return VStack(alignment: .leading, spacing: 10) {
            StrideSectionHeading(title: "MILESTONES", trailing: "PERSONAL BESTS", style: style)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Image(row.2).resizable().scaledToFit()
                            .frame(width: 43, height: 43)
                            .accessibilityHidden(true)
                        Rectangle().fill(style.accent).frame(width: 2, height: 34)
                        Text(row.0).font(.barlowCondensed(size: 21))
                        Spacer()
                        Text(row.1).font(.barlowCondensed(size: 24))
                            .foregroundStyle(row.1 == "—" ? style.muted : style.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    if index < rows.count - 1 {
                        Rectangle().fill(style.rule).frame(height: 0.5).padding(.horizontal, 14)
                    }
                }
            }
            .stridePageCard(style)
        }
    }

    private var deeperInsights: some View {
        VStack(alignment: .leading, spacing: 12) {
            StrideSectionHeading(title: "DEEPER INSIGHTS", trailing: "THE FULL PICTURE", style: style)
            StatsDeepInsightsView(runLogs: runLogs, plan: plan, style: style)
        }
    }

    private func paceText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct StatsSparkline: View {
    let values: [Double]
    let reverse: Bool
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            let finite = values.filter { $0.isFinite && $0 > 0 }
            if finite.count >= 2 {
                let minimum = finite.min() ?? 0
                let maximum = max(minimum + 1, finite.max() ?? 1)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let normalized = value > 0 ? (value - minimum) / (maximum - minimum) : 0
                        let y = 5 + (geometry.size.height - 10) * CGFloat(reverse ? normalized : 1 - normalized)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.06), .clear],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let normalized = value > 0 ? (value - minimum) / (maximum - minimum) : 0
                        let fraction = reverse ? normalized : 1 - normalized
                        let y = 5 + (geometry.size.height - 10) * CGFloat(fraction)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.25), radius: 3)
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                    let normalized = value > 0 ? (value - minimum) / (maximum - minimum) : 0
                    let y = 5 + (geometry.size.height - 10) * CGFloat(reverse ? normalized : 1 - normalized)
                    Circle().fill(color).frame(width: 3, height: 3).position(x: x, y: y)
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }.stroke(color.opacity(0.30), lineWidth: 1)
            }
        }
        .accessibilityLabel("Training trend")
    }
}

// MARK: - Deeper insights in the same visual system as Run and Plan

private struct StatsDeepInsightsView: View {
    let runLogs: [RunLog]
    let plan: TrainingPlan?
    let style: StridePageStyle

    private var calendar: Calendar { StatsTrainingData.calendar() }
    private var insight: TrainingInsightSummary { .init(runLogs: runLogs, heartRateType: .easyRun) }
    private var weeklyLoad: [(date: Date, actual: Double, planned: Double)] {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let actual = runLogs.filter { $0.completedAt >= start && $0.completedAt < end }
                .reduce(0.0) { $0 + $1.distanceKm }
            let planned = plan?.sortedWeeks.first { week in
                guard let monday = week.mondayStart else { return false }
                return calendar.isDate(monday, inSameDayAs: start)
            }?.workouts.filter { $0.workoutType.isRunnable }
                .reduce(0.0) { $0 + ($1.distanceKm ?? 0) } ?? 0
            return (start, actual, planned)
        }
    }
    private var longRunWeeks: [(number: Int, actual: Double, planned: Double)] {
        guard let plan else { return [] }
        let model = StatsViewModel(plan: plan, runLogs: runLogs)
        let actuals = Dictionary(uniqueKeysWithValues: model.longRunActualProgression.map { ($0.weekNumber, $0.distance) })
        let currentWeek = plan.currentWeek?.weekNumber ?? plan.sortedWeeks.first?.weekNumber ?? 1
        return Array(model.longRunProgression.filter { $0.weekNumber <= currentWeek }.suffix(8))
            .map { ($0.weekNumber, actuals[$0.weekNumber] ?? 0, $0.distance) }
    }

    var body: some View {
        VStack(spacing: 11) {
            weeklyLoadCard
            heartRateCard
            feelingCard
            if plan != nil {
                longRunCard
                compositionCard
            }
        }
    }

    private var weeklyLoadCard: some View {
        let weeks = weeklyLoad
        let maximum = max(1, weeks.map { max($0.actual, $0.planned) }.max() ?? 1)
        return insightCard(eyebrow: "01 / TRAINING LOAD", title: "THE LAST 8 WEEKS", footnote: "RED / COMPLETED     GREY / PLANNED") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.0f", weeks.last?.actual ?? 0))
                    .font(.barlowCondensed(size: 43))
                Text("KM THIS WEEK").font(.runEyebrow(9)).foregroundStyle(style.muted)
                Spacer()
                if let target = weeks.last?.planned, target > 0 {
                    Text(String(format: "/ %.0f KM", target))
                        .font(.barlowCondensed(size: 24)).foregroundStyle(style.muted)
                }
            }
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(style.ink.opacity(0.16))
                                .frame(height: max(2, 92 * week.planned / maximum))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(style.accent)
                                .frame(height: max(2, 92 * week.actual / maximum))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        Text(week.date.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .font(.runEyebrow(7)).foregroundStyle(style.muted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112)
        }
    }

    private var heartRateCard: some View {
        let summary = insight
        let values = summary.weeks.map(\.heartRate)
        return insightCard(eyebrow: "02 / EASY RUN EFFORT", title: "HEART RATE TREND", footnote: "EASY RUNS / LAST 8 WEEKS") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summary.recentHR.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.barlowCondensed(size: 43))
                Text("BPM / RECENT AVG").font(.runEyebrow(9)).foregroundStyle(style.muted)
                Spacer()
                if let percent = summary.inRangePercent {
                    Text(String(format: "%.0f%% IN ZONE", percent))
                        .font(.runEyebrow(9)).foregroundStyle(style.accent)
                }
            }
            StatsInsightPlot(values: values, bounds: 120...160, line: style.accent, guide: .blue,
                             showTarget: true)
                .frame(height: 104)
            HStack {
                Text("120 BPM").font(.runEyebrow(8))
                Spacer()
                Text("160 BPM").font(.runEyebrow(8))
            }
            .foregroundStyle(style.muted)
            Rectangle().fill(style.rule).frame(height: 0.5)
            HStack(spacing: 8) {
                heartRateTypeMetric("EASY", summary: summary)
                heartRateTypeMetric("LONG", summary: .init(runLogs: runLogs, heartRateType: .longRun))
                heartRateTypeMetric("RECOVERY", summary: .init(runLogs: runLogs, heartRateType: .recovery))
            }
        }
    }

    private func heartRateTypeMetric(_ label: String, summary: TrainingInsightSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.runEyebrow(8)).foregroundStyle(style.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(summary.recentHR.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.barlowCondensed(size: 24))
                Text("BPM").font(.runEyebrow(8)).foregroundStyle(style.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feelingCard: some View {
        let summary = insight
        return insightCard(eyebrow: "03 / POST-RUN FEEDBACK", title: "HOW RUNS FEEL", footnote: "RATED RUNS ONLY / 0–5 SCALE") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(summary.recentFeeling.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.barlowCondensed(size: 43))
                Text("/ 5 RECENT AVG").font(.runEyebrow(9)).foregroundStyle(style.muted)
                Spacer()
                Text("\(summary.ratedCount) RATED")
                    .font(.runEyebrow(9)).foregroundStyle(style.muted)
            }
            if summary.weeks.contains(where: { $0.feeling != nil }) {
                StatsInsightPlot(values: summary.weeks.map(\.feeling), bounds: 0...5,
                                 line: .pink, guide: style.muted, showTarget: false)
                    .frame(height: 86)
            } else {
                Text("Rate a run after finishing to start your trend.")
                    .font(.inter(size: 11)).foregroundStyle(style.muted)
            }
        }
    }

    private var longRunCard: some View {
        let weeks = longRunWeeks
        let recent = weeks.last(where: { $0.actual > 0 })
        let maximum = max(1, weeks.map { max($0.actual, $0.planned) }.max() ?? 1)
        return insightCard(eyebrow: "04 / ENDURANCE BUILD", title: "LONG RUN PROGRESSION", footnote: "LAST 8 WEEKS     RED / COMPLETED     GREY / PLAN") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(recent.map { String(format: "%.0f", $0.actual) } ?? "—")
                    .font(.barlowCondensed(size: 43))
                Text("KM / LAST LONG RUN").font(.runEyebrow(9)).foregroundStyle(style.muted)
                Spacer()
                if let peak = weeks.map(\.planned).max(), peak > 0 {
                    Text(String(format: "%.0f KM PEAK", peak))
                        .font(.runEyebrow(9)).foregroundStyle(style.muted)
                }
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(style.ink.opacity(0.16))
                                .frame(height: max(2, 92 * week.planned / maximum))
                            if week.actual > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(style.accent)
                                    .frame(height: max(2, 92 * week.actual / maximum))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        Text("W\(week.number)").font(.runEyebrow(7)).foregroundStyle(style.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112)
        }
    }

    private var compositionCard: some View {
        let model = plan.map { StatsViewModel(plan: $0, runLogs: runLogs) }
        let breakdown = plan?.currentWeek.map { model?.intensityBreakdown(for: $0) ?? [:] } ?? [:]
        let buckets: [(IntensityBucket, Color)] = [(.easy, .blue), (.moderate, style.accent), (.hard, .pink)]
        let total = breakdown.values.reduce(0, +)
        return insightCard(eyebrow: "05 / THIS WEEK", title: "TRAINING MIX", footnote: "PLANNED DISTANCE / BY EFFORT") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(String(format: "%.0f", total)).font(.barlowCondensed(size: 43))
                Text("KM PLANNED").font(.runEyebrow(9)).foregroundStyle(style.muted)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(buckets, id: \.0) { bucket, color in
                        let value = breakdown[bucket] ?? 0
                        if value > 0 {
                            Rectangle().fill(color)
                                .frame(width: max(1, (geometry.size.width - 4) * value / max(1, total)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.ink.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 11)
            HStack(spacing: 13) {
                ForEach(buckets, id: \.0) { bucket, color in
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 5, height: 5)
                        Text(bucket.displayName.uppercased()).font(.runEyebrow(8))
                        Text(String(format: "%.0f%%", total > 0 ? (breakdown[bucket] ?? 0) / total * 100 : 0))
                            .font(.runEyebrow(8)).foregroundStyle(style.muted)
                    }
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func insightCard<Content: View>(eyebrow: String, title: String, footnote: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow).font(.runEyebrow(9)).tracking(1).foregroundStyle(style.accent)
            Text(title).font(.barlowCondensed(size: 26))
            content()
            Rectangle().fill(style.rule).frame(height: 0.5)
            Text(footnote).font(.runEyebrow(8)).foregroundStyle(style.muted)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stridePageCard(style)
    }
}

private struct StatsInsightPlot: View {
    let values: [Double?]
    let bounds: ClosedRange<Double>
    let line: Color
    let guide: Color
    let showTarget: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                if showTarget {
                    Rectangle().fill(guide.opacity(0.06))
                        .frame(height: height * 0.43)
                    ForEach([0.28, 0.71], id: \.self) { fraction in
                        Path { path in
                            let y = height * fraction
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                        .stroke(guide.opacity(0.55), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                    }
                }
                Path { path in
                    var lastX: CGFloat?
                    for (index, value) in values.enumerated() {
                        guard let value else {
                            if let lastX {
                                path.addLine(to: CGPoint(x: lastX, y: height))
                                path.closeSubpath()
                            }
                            lastX = nil
                            continue
                        }
                        let x = width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let fraction = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
                        let y = height * CGFloat(1 - min(1, max(0, fraction)))
                        if lastX == nil {
                            path.move(to: CGPoint(x: x, y: height))
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        lastX = x
                    }
                    if let lastX {
                        path.addLine(to: CGPoint(x: lastX, y: height))
                        path.closeSubpath()
                    }
                }
                .fill(LinearGradient(colors: [line.opacity(0.28), line.opacity(0.08), .clear],
                                     startPoint: .top, endPoint: .bottom))
                Path { path in
                    var drawing = false
                    for (index, value) in values.enumerated() {
                        guard let value else { drawing = false; continue }
                        let x = width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let fraction = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
                        let y = height * CGFloat(1 - min(1, max(0, fraction)))
                        if drawing { path.addLine(to: CGPoint(x: x, y: y)) }
                        else { path.move(to: CGPoint(x: x, y: y)); drawing = true }
                    }
                }
                .stroke(line, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: line.opacity(0.30), radius: 4)
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if let value {
                        let x = width * CGFloat(index) / CGFloat(max(1, values.count - 1))
                        let fraction = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
                        let y = height * CGFloat(1 - min(1, max(0, fraction)))
                        Circle().fill(line).frame(width: 5, height: 5).position(x: x, y: y)
                    }
                }
            }
        }
        .accessibilityLabel("Eight-week easy-run heart rate trend")
    }
}
