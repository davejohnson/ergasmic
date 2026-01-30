import SwiftUI

struct BuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BuilderViewModel
    @State private var showTemplatePicker: Bool
    let onSave: (Workout) -> Void

    init(workout: Workout, onSave: @escaping (Workout) -> Void) {
        let vm = BuilderViewModel(workout: workout)
        _viewModel = StateObject(wrappedValue: vm)
        // Show template picker automatically for new empty workouts
        _showTemplatePicker = State(initialValue: workout.steps.isEmpty)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if showTemplatePicker {
                    Section {
                        ForEach(BuilderViewModel.WorkoutTemplate.allCases) { template in
                            Button {
                                viewModel.applyTemplate(template)
                                showTemplatePicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: template.icon)
                                        .frame(width: 24)
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.rawValue)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(template.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Choose a Template")
                    } footer: {
                        Text("Pick a starting point, then customize the steps.")
                    }
                }

                Section("Workout Info") {
                    TextField("Name", text: $viewModel.name)
                    TextField("Notes", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    ForEach(Array(viewModel.steps.enumerated()), id: \.element.id) { index, step in
                        StepRowView(step: step) {
                            viewModel.editingStepIndex = index
                            viewModel.editingChildIndex = nil
                            viewModel.showStepEditor = true
                        }
                    }
                    .onMove { from, to in
                        viewModel.steps.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        viewModel.steps.remove(atOffsets: offsets)
                    }

                    Menu {
                        Button {
                            viewModel.addSteadyStep()
                        } label: {
                            Label("Steady", systemImage: "minus")
                        }

                        Button {
                            viewModel.addRampStep()
                        } label: {
                            Label("Ramp", systemImage: "arrow.up.right")
                        }

                        Button {
                            viewModel.addRepeatBlock()
                        } label: {
                            Label("Repeat Block", systemImage: "repeat")
                        }

                        Button {
                            viewModel.addHRTargetStep()
                        } label: {
                            Label("HR Target", systemImage: "heart")
                        }
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Steps")
                        Spacer()
                        Text("Total: \(viewModel.totalDuration)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = viewModel.validationError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(viewModel.isNew ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let workout = viewModel.buildWorkout() {
                            onSave(workout)
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .sheet(isPresented: $viewModel.showStepEditor) {
                if let index = viewModel.editingStepIndex {
                    if viewModel.steps[index].type == .repeats {
                        RepeatBlockEditorView(
                            step: $viewModel.steps[index],
                            onEditChild: { childIndex in
                                viewModel.editingChildIndex = childIndex
                                viewModel.showChildEditor = true
                            }
                        )
                    } else {
                        StepEditorView(step: $viewModel.steps[index])
                    }
                }
            }
            .sheet(isPresented: $viewModel.showChildEditor) {
                if let stepIndex = viewModel.editingStepIndex,
                   let childIndex = viewModel.editingChildIndex {
                    StepEditorView(step: $viewModel.steps[stepIndex].children[childIndex])
                }
            }
        }
    }
}

struct StepRowView: View {
    let step: WorkoutStep
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                stepIcon
                    .foregroundColor(stepColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.displayDescription)
                        .font(.body)

                    if step.type == .repeats && !step.children.isEmpty {
                        Text(childrenSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(stepTypeLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var stepIcon: some View {
        Group {
            switch step.type {
            case .steady:
                Image(systemName: "minus")
            case .ramp:
                Image(systemName: "arrow.up.right")
            case .repeats:
                Image(systemName: "repeat")
            case .hrTarget:
                Image(systemName: "heart")
            }
        }
    }

    private var stepTypeLabel: String {
        switch step.type {
        case .steady:
            return "Steady"
        case .ramp:
            return "Ramp"
        case .repeats:
            return "Repeat \(step.repeatCount)x"
        case .hrTarget:
            return "HR Target"
        }
    }

    private var childrenSummary: String {
        let childDescriptions = step.children.map { child -> String in
            switch child.type {
            case .steady:
                return "\(child.intensityPct)%"
            case .ramp:
                return "\(child.startPct)→\(child.endPct)%"
            case .repeats:
                return "nested"
            case .hrTarget:
                return "HR \(child.targetHRLow)-\(child.targetHRHigh)"
            }
        }
        return "\(step.repeatCount)x: " + childDescriptions.joined(separator: ", ")
    }

    private var stepColor: Color {
        switch step.type {
        case .steady:
            return .blue
        case .ramp:
            return .orange
        case .repeats:
            return .purple
        case .hrTarget:
            return .red
        }
    }
}

struct StepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var step: WorkoutStep

    @State private var durationMinutes: Int
    @State private var durationSeconds: Int
    @State private var intensityPct: Int
    @State private var startPct: Int
    @State private var endPct: Int
    @State private var targetHRLow: Int
    @State private var targetHRHigh: Int
    @State private var fallbackPct: Int

    init(step: Binding<WorkoutStep>) {
        self._step = step
        let duration = step.wrappedValue.durationSec
        _durationMinutes = State(initialValue: duration / 60)
        _durationSeconds = State(initialValue: duration % 60)
        _intensityPct = State(initialValue: step.wrappedValue.intensityPct)
        _startPct = State(initialValue: step.wrappedValue.startPct)
        _endPct = State(initialValue: step.wrappedValue.endPct)
        _targetHRLow = State(initialValue: step.wrappedValue.targetHRLow)
        _targetHRHigh = State(initialValue: step.wrappedValue.targetHRHigh)
        _fallbackPct = State(initialValue: step.wrappedValue.fallbackPct)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    Stepper("\(durationMinutes) min", value: $durationMinutes, in: 0...180)
                    Stepper("\(durationSeconds) sec", value: $durationSeconds, in: 0...59, step: 5)
                }

                switch step.type {
                case .steady:
                    Section("Intensity") {
                        Stepper("\(intensityPct)% FTP", value: $intensityPct, in: 30...200, step: 5)
                        intensityPreview(percent: intensityPct)
                    }

                case .ramp:
                    Section("Start Intensity") {
                        Stepper("\(startPct)% FTP", value: $startPct, in: 30...200, step: 5)
                        intensityPreview(percent: startPct)
                    }
                    Section("End Intensity") {
                        Stepper("\(endPct)% FTP", value: $endPct, in: 30...200, step: 5)
                        intensityPreview(percent: endPct)
                    }

                case .repeats:
                    EmptyView()

                case .hrTarget:
                    Section("Target Heart Rate") {
                        Stepper("Low: \(targetHRLow) bpm", value: $targetHRLow, in: 50...220)
                        Stepper("High: \(targetHRHigh) bpm", value: $targetHRHigh, in: 50...220)
                    }
                    Section("Fallback Power") {
                        Stepper("\(fallbackPct)% FTP", value: $fallbackPct, in: 30...200, step: 5)
                        Text("Used until HR stabilizes or if HR data is unavailable")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func intensityPreview(percent: Int) -> some View {
        let zone = TargetCalculator(ftp: 200).zoneForPercent(percent)
        return HStack {
            Text("Zone: \(zone.rawValue)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func applyChanges() {
        step.durationSec = durationMinutes * 60 + durationSeconds
        step.intensityPct = intensityPct
        step.startPct = startPct
        step.endPct = endPct
        step.targetHRLow = targetHRLow
        step.targetHRHigh = targetHRHigh
        step.fallbackPct = fallbackPct
    }
}

struct RepeatBlockEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var step: WorkoutStep
    let onEditChild: (Int) -> Void

    @State private var repeatCount: Int

    init(step: Binding<WorkoutStep>, onEditChild: @escaping (Int) -> Void) {
        self._step = step
        self.onEditChild = onEditChild
        _repeatCount = State(initialValue: step.wrappedValue.repeatCount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat Count") {
                    Stepper("\(repeatCount) times", value: $repeatCount, in: 2...50)
                }

                Section {
                    ForEach(Array(step.children.enumerated()), id: \.element.id) { index, child in
                        Button {
                            step.repeatCount = repeatCount
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onEditChild(index)
                            }
                        } label: {
                            HStack {
                                childIcon(for: child)
                                    .foregroundColor(childColor(for: child))
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text(child.displayDescription)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(childTypeLabel(for: child))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        step.children.remove(atOffsets: offsets)
                    }

                    Menu {
                        Button {
                            let newStep = WorkoutStep.steady(durationSec: 60, intensityPct: 120)
                            step.children.append(newStep)
                        } label: {
                            Label("Add Steady", systemImage: "minus")
                        }

                        Button {
                            let newStep = WorkoutStep.ramp(durationSec: 60, startPct: 80, endPct: 120)
                            step.children.append(newStep)
                        } label: {
                            Label("Add Ramp", systemImage: "arrow.up.right")
                        }
                    } label: {
                        Label("Add Step to Block", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Steps in Block")
                        Spacer()
                        Text("Per rep: \(formatChildrenDuration())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Total duration: \(formatTotalDuration())")
                }
            }
            .navigationTitle("Edit Repeat Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        step.repeatCount = repeatCount
                        dismiss()
                    }
                }
            }
        }
    }

    private func childIcon(for child: WorkoutStep) -> some View {
        Group {
            switch child.type {
            case .steady:
                Image(systemName: "minus")
            case .ramp:
                Image(systemName: "arrow.up.right")
            case .repeats:
                Image(systemName: "repeat")
            case .hrTarget:
                Image(systemName: "heart")
            }
        }
    }

    private func childColor(for child: WorkoutStep) -> Color {
        switch child.type {
        case .steady:
            return .blue
        case .ramp:
            return .orange
        case .repeats:
            return .purple
        case .hrTarget:
            return .red
        }
    }

    private func childTypeLabel(for child: WorkoutStep) -> String {
        switch child.type {
        case .steady:
            return "Steady"
        case .ramp:
            return "Ramp"
        case .repeats:
            return "Repeat"
        case .hrTarget:
            return "HR Target"
        }
    }

    private func formatChildrenDuration() -> String {
        let totalSec = step.children.reduce(0) { $0 + $1.durationSec }
        return formatDuration(totalSec)
    }

    private func formatTotalDuration() -> String {
        let perRep = step.children.reduce(0) { $0 + $1.durationSec }
        return formatDuration(perRep * repeatCount)
    }
}

#Preview {
    BuilderView(workout: Workout()) { _ in }
}
