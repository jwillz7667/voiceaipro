import SwiftUI

/// Slider with label and value display
struct SliderWithLabel: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    var unit: String = ""
    var icon: String? = nil
    var description: String? = nil
    var formatter: ((Double) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 24)
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Text(displayValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
            }

            if let step = step {
                Slider(value: $value, in: range, step: step)
                    .tint(.blue)
                    .onChange(of: value) { _, _ in
                        let generator = UISelectionFeedbackGenerator()
                        generator.selectionChanged()
                    }
            } else {
                Slider(value: $value, in: range)
                    .tint(.blue)
            }

            if let description = description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var displayValue: String {
        if let formatter = formatter {
            return formatter(value)
        }
        if let step = step, step >= 1 {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.2f", value) + unit
    }
}

/// Integer slider with stepper-like controls
struct IntSliderWithLabel: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""
    var icon: String? = nil
    var description: String? = nil
    var specialValues: [Int: String] = [:] // e.g., [0: "None", 4096: "Max"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 24)
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Text(displayValue)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(.blue)
            .onChange(of: value) { _, _ in
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
            }

            if let description = description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var displayValue: String {
        if let special = specialValues[value] {
            return special
        }
        return "\(value)\(unit)"
    }
}

/// Stepper row for precise integer control
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24)
            }

            Text(title)
                .font(.system(size: 16, weight: .medium))

            Spacer()

            HStack(spacing: 0) {
                Button(action: {
                    if value - step >= range.lowerBound {
                        value -= step
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(value <= range.lowerBound ? .secondary : .blue)
                        .frame(width: 36, height: 32)
                }
                .disabled(value <= range.lowerBound)

                Text("\(value)\(unit)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(minWidth: 50)

                Button(action: {
                    if value + step <= range.upperBound {
                        value += step
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(value >= range.upperBound ? .secondary : .blue)
                        .frame(width: 36, height: 32)
                }
                .disabled(value >= range.upperBound)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 20) {
                GlassCard {
                    VStack(spacing: 20) {
                        SliderWithLabel(
                            title: "Temperature",
                            value: .constant(0.8),
                            range: 0.6...1.2,
                            icon: "thermometer.medium",
                            description: "Higher = more creative responses"
                        )

                        Divider()

                        SliderWithLabel(
                            title: "Voice Speed",
                            value: .constant(1.0),
                            range: 0.5...1.5,
                            step: 0.1,
                            unit: "x",
                            icon: "gauge.with.needle"
                        )

                        Divider()

                        IntSliderWithLabel(
                            title: "Silence Duration",
                            value: .constant(500),
                            range: 200...2000,
                            step: 100,
                            unit: "ms",
                            icon: "waveform.slash"
                        )
                    }
                }

                GlassCard {
                    StepperRow(
                        title: "Max Tokens",
                        value: .constant(4096),
                        range: 256...8192,
                        step: 256,
                        icon: "text.word.spacing"
                    )
                }
            }
            .padding()
        }
    }
}
