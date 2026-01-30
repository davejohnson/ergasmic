import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var bleManager: BLEManager
    @StateObject private var viewModel = DevicesViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Connected Devices Section
                        connectedDevicesSection

                        // Discovered Devices Section
                        discoveredDevicesSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    scanButton
                }
            }
        }
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        Button {
            if bleManager.isScanning {
                bleManager.stopScanning()
            } else {
                bleManager.startScanning()
            }
        } label: {
            if bleManager.isScanning {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning")
                        .font(.subheadline)
                }
                .foregroundColor(.blue)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Scan")
                        .font(.subheadline)
                }
            }
        }
        .disabled(bleManager.centralState != .poweredOn)
    }

    // MARK: - Connected Devices Section

    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTED")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // Trainer
                ConnectedDeviceCard(
                    icon: "bicycle",
                    iconColor: .blue,
                    title: "Trainer",
                    subtitle: bleManager.trainerDevice?.peripheral.name ?? "Not connected",
                    status: bleManager.trainerConnectionState,
                    isConnected: bleManager.trainerDevice != nil,
                    onDisconnect: {
                        bleManager.disconnectTrainer()
                    }
                )

                // Heart Rate Monitor
                ConnectedDeviceCard(
                    icon: "heart.fill",
                    iconColor: .red,
                    title: "Heart Rate",
                    subtitle: bleManager.heartRateDevice?.peripheral.name ?? "Not connected",
                    status: bleManager.heartRateConnectionState,
                    isConnected: bleManager.heartRateDevice != nil,
                    onDisconnect: {
                        bleManager.disconnectHeartRate()
                    }
                )
            }
        }
    }

    // MARK: - Discovered Devices Section

    private var fitnessDevices: [DiscoveredDevice] {
        bleManager.discoveredDevices.filter { $0.isTrainer || $0.isHeartRate || $0.isCadence }
    }

    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AVAILABLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                Spacer()

                if !fitnessDevices.isEmpty {
                    Text("\(fitnessDevices.count) found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if fitnessDevices.isEmpty {
                emptyDiscoveredState
            } else {
                VStack(spacing: 8) {
                    ForEach(fitnessDevices) { device in
                        DiscoveredDeviceCard(device: device) {
                            if device.isTrainer {
                                bleManager.connectTrainer(device)
                            } else if device.isHeartRate {
                                bleManager.connectHeartRate(device)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyDiscoveredState: some View {
        VStack(spacing: 12) {
            if bleManager.isScanning {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching for devices...")
                        .foregroundColor(.secondary)
                }
            } else if bleManager.centralState != .poweredOn {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Bluetooth is off")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Enable Bluetooth in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No devices found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap Scan to search for devices")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Connected Device Card

struct ConnectedDeviceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let status: BLEConnectionState
    let isConnected: Bool
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? iconColor : .secondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Disconnect button
            if isConnected {
                Button {
                    onDisconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            } else {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isConnected ? iconColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .ready: return .green
        case .connected: return .green
        case .connecting: return .yellow
        case .scanning: return .blue
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .ready: return "Ready"
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .scanning: return "Scanning..."
        case .disconnected: return "Not connected"
        }
    }
}

// MARK: - Discovered Device Card

struct DiscoveredDeviceCard: View {
    let device: DiscoveredDevice
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 14) {
                // Device type icon
                ZStack {
                    Circle()
                        .fill(deviceColor.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: deviceIcon)
                        .font(.system(size: 16))
                        .foregroundColor(deviceColor)
                }

                // Device info
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if device.isTrainer {
                            DeviceTypeBadge(text: "Trainer", color: .blue)
                        }
                        if device.isHeartRate {
                            DeviceTypeBadge(text: "HR", color: .red)
                        }
                        if device.isCadence {
                            DeviceTypeBadge(text: "Cadence", color: .orange)
                        }
                    }
                }

                Spacer()

                // Signal strength
                VStack(alignment: .trailing, spacing: 2) {
                    SignalStrengthIndicator(rssi: device.rssi)
                    Text("\(device.rssi) dBm")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var deviceIcon: String {
        if device.isTrainer { return "bicycle" }
        if device.isHeartRate { return "heart.fill" }
        if device.isCadence { return "circle.dotted" }
        return "antenna.radiowaves.left.and.right"
    }

    private var deviceColor: Color {
        if device.isTrainer { return .blue }
        if device.isHeartRate { return .red }
        if device.isCadence { return .orange }
        return .secondary
    }
}

struct DeviceTypeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

struct SignalStrengthIndicator: View {
    let rssi: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: CGFloat(4 + index * 3))
            }
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold: Int
        switch index {
        case 0: threshold = -90
        case 1: threshold = -75
        case 2: threshold = -60
        default: threshold = -45
        }
        return rssi >= threshold ? signalColor : .gray.opacity(0.3)
    }

    private var signalColor: Color {
        if rssi >= -60 { return .green }
        if rssi >= -75 { return .yellow }
        return .orange
    }
}

#Preview {
    DevicesView()
        .environmentObject(BLEManager())
}
