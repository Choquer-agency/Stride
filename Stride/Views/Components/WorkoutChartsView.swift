import SwiftUI
import Charts

/// Swift Charts for workout visualization
struct WorkoutChartsView: View {
    let session: WorkoutSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Pace over time
            VStack(alignment: .leading, spacing: 8) {
                Text("Pace over time")
                    .font(.headline)
                    .padding(.horizontal)
                
                Chart {
                    ForEach(session.recentSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp.timeIntervalSince(session.startTime)),
                            y: .value("Pace", sample.paceSecPerKm)
                        )
                        .foregroundStyle(.green)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(seconds.toTimeString())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let pace = value.as(Double.self) {
                                Text(pace.toPaceString())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Distance over time
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance over time")
                    .font(.headline)
                    .padding(.horizontal)
                
                Chart {
                    ForEach(session.recentSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp.timeIntervalSince(session.startTime)),
                            y: .value("Distance", sample.totalDistanceMeters / 1000.0)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(seconds.toTimeString())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text(String(format: "%.1f km", km))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Speed over time
            VStack(alignment: .leading, spacing: 8) {
                Text("Speed over time")
                    .font(.headline)
                    .padding(.horizontal)
                
                Chart {
                    ForEach(session.recentSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp.timeIntervalSince(session.startTime)),
                            y: .value("Speed", sample.speedMps * 3.6)
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(seconds.toTimeString())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let speed = value.as(Double.self) {
                                Text(String(format: "%.1f km/h", speed))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }
}

