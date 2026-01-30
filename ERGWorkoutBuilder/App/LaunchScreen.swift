import SwiftUI

struct LaunchScreen: View {
    @State private var isAnimating = false
    @State private var powerValue = 0
    @State private var showTagline = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Animated background circles
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.3),
                                    Color.purple.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 200 + CGFloat(index * 80), height: 200 + CGFloat(index * 80))
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                        .opacity(isAnimating ? 0.5 : 0.2)
                        .animation(
                            .easeInOut(duration: 2)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: isAnimating
                        )
                }
            }

            VStack(spacing: 40) {
                // Power meter ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 12)
                        .frame(width: 160, height: 160)

                    // Animated power ring
                    Circle()
                        .trim(from: 0, to: isAnimating ? 0.75 : 0)
                        .stroke(
                            AngularGradient(
                                colors: [.blue, .cyan, .green, .yellow, .orange, .red],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1.5), value: isAnimating)

                    // Center content
                    VStack(spacing: 4) {
                        Text("\(powerValue)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Text("WATTS")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .tracking(2)
                    }
                }

                // App name
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("ERG")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("tastic")
                            .font(.system(size: 48, weight: .light, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }

                    if showTagline {
                        Text("STRUCTURED TRAINING")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(4)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeOut(duration: 0.5).delay(0.8), value: showTagline)
            }
        }
        .onAppear {
            isAnimating = true
            showTagline = true
            animatePower()
        }
    }

    private func animatePower() {
        let targetPower = 285
        let steps = 30
        let interval = 1.2 / Double(steps)

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                withAnimation(.none) {
                    powerValue = Int(Double(targetPower) * Double(i) / Double(steps))
                }
            }
        }
    }
}

#Preview {
    LaunchScreen()
}
