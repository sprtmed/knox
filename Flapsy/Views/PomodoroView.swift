import SwiftUI

// MARK: - Timer Model

class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    enum TimerState { case idle, running, paused }
    enum SessionType: Hashable { case work, shortBreak, longBreak }

    private var timer: Timer?

    // Classic
    @Published var classicState: TimerState = .idle
    @Published var sessionType: SessionType = .work
    @Published var timeRemaining: Int = 25 * 60
    @Published var workSessionNumber: Int = 1

    // Mode
    @Published var showBlockMode: Bool = false

    // Block
    @Published var blockState: TimerState = .idle
    @Published var blockGoal: Int = 20
    @Published var blockDuration: Int = 5
    @Published var completedBlocks: Int = 0
    @Published var blockTimeRemaining: Int = 5 * 60
    @Published var showCelebration: Bool = false
    @Published var celebrationBlockIndex: Int? = nil
    @Published var celebrationText: String = ""
    @Published var pendingBlockIndex: Int? = nil

    private let celebrations = [
        "Nice!", "Great job!", "Keep going!",
        "Crushing it!", "On fire!", "Locked in!",
        "Beast mode!", "Unstoppable!", "Let's go!",
        "Nailed it!", "Boom!", "Yes!"
    ]

    private init() {}

    var sessionsUntilLongBreak: Int { max(0, 4 - workSessionNumber) }
    var totalBlockMinutes: Int { blockGoal * blockDuration }

    func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func duration(for type: SessionType) -> Int {
        switch type {
        case .work: return 25 * 60
        case .shortBreak: return 5 * 60
        case .longBreak: return 30 * 60
        }
    }

    func sessionLabel(_ type: SessionType) -> String {
        switch type {
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    func sessionMinutes(_ type: SessionType) -> Int {
        duration(for: type) / 60
    }

    // MARK: Classic

    func selectSession(_ type: SessionType) {
        guard classicState == .idle else { return }
        sessionType = type
        timeRemaining = duration(for: type)
    }

    func startClassic() {
        classicState = .running
        runTimer { [weak self] in
            guard let self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.classicCompleted()
            }
        }
    }

    func pauseClassic() {
        classicState = .paused
        timer?.invalidate()
    }

    func resumeClassic() {
        classicState = .running
        runTimer { [weak self] in
            guard let self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.classicCompleted()
            }
        }
    }

    func resetClassic() {
        classicState = .idle
        timer?.invalidate()
        sessionType = .work
        timeRemaining = duration(for: .work)
        workSessionNumber = 1
    }

    private func classicCompleted() {
        timer?.invalidate()
        classicState = .idle

        switch sessionType {
        case .work:
            if workSessionNumber >= 4 {
                sessionType = .longBreak
            } else {
                sessionType = .shortBreak
            }
        case .shortBreak:
            workSessionNumber += 1
            sessionType = .work
        case .longBreak:
            workSessionNumber = 1
            sessionType = .work
        }
        timeRemaining = duration(for: sessionType)
    }

    // MARK: Block

    func startBlock() {
        blockState = .running
        showCelebration = false
        celebrationBlockIndex = nil
        blockTimeRemaining = blockDuration * 60
        runTimer { [weak self] in
            guard let self else { return }
            if self.blockTimeRemaining > 0 {
                self.blockTimeRemaining -= 1
            } else {
                self.blockCompleted()
            }
        }
    }

    func pauseBlock() {
        blockState = .paused
        timer?.invalidate()
    }

    func resumeBlock() {
        blockState = .running
        runTimer { [weak self] in
            guard let self else { return }
            if self.blockTimeRemaining > 0 {
                self.blockTimeRemaining -= 1
            } else {
                self.blockCompleted()
            }
        }
    }

    private func blockCompleted() {
        timer?.invalidate()
        blockState = .idle
        pendingBlockIndex = completedBlocks
        blockTimeRemaining = blockDuration * 60
    }

    func claimBlock() {
        guard let index = pendingBlockIndex else { return }
        celebrationBlockIndex = index
        completedBlocks = min(completedBlocks + 1, blockGoal)
        celebrationText = celebrations.randomElement() ?? "Nice!"
        pendingBlockIndex = nil
        showCelebration = true
    }

    func dismissCelebration() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCelebration = false
            celebrationBlockIndex = nil
        }
    }

    func setBlockGoal(_ goal: Int) {
        guard blockState == .idle else { return }
        blockGoal = goal
        completedBlocks = min(completedBlocks, goal)
    }

    func setBlockDuration(_ minutes: Int) {
        guard blockState == .idle else { return }
        blockDuration = minutes
        blockTimeRemaining = minutes * 60
    }

    func setHoursGoal(_ hours: Int) {
        let blocks = (hours * 60) / blockDuration
        setBlockGoal(max(1, blocks))
    }

    func resetBlocks() {
        timer?.invalidate()
        blockState = .idle
        completedBlocks = 0
        blockTimeRemaining = blockDuration * 60
        showCelebration = false
        celebrationBlockIndex = nil
        pendingBlockIndex = nil
    }

    // MARK: Shared

    func stopAll() {
        timer?.invalidate()
        if classicState == .running { classicState = .paused }
        if blockState == .running { blockState = .paused }
    }

    private func runTimer(action: @escaping () -> Void) {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { _ in action() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Main View

struct PomodoroView: View {
    @Environment(\.theme) var theme
    @ObservedObject private var timer = PomodoroTimer.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if timer.showBlockMode {
                    BlockTimerView(timer: timer)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    ClassicPomodoroView(timer: timer)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

// MARK: - Classic Pomodoro View

private struct ClassicPomodoroView: View {
    @Environment(\.theme) var theme
    @ObservedObject var timer: PomodoroTimer

    private let sessionTypes: [PomodoroTimer.SessionType] = [.work, .shortBreak, .longBreak]

    var body: some View {
        VStack(spacing: 20) {
            sessionSelector

            VStack(spacing: 6) {
                Text(timer.formatTime(timer.timeRemaining))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundColor(theme.text)
                    .monospacedDigit()

                Text(timer.sessionType == .work ? "Focus Time" : "Break Time")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(theme.textSecondary)
            }
            .padding(.vertical, 16)

            controls

            Divider()
                .background(theme.cardBorder)
                .padding(.vertical, 8)

            Text("Session \(timer.workSessionNumber) \u{2022} \(timer.sessionsUntilLongBreak) until long break")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.textMuted)
                .padding(.bottom, 8)
        }
    }

    private var sessionSelector: some View {
        HStack(spacing: 8) {
            ForEach(sessionTypes, id: \.self) { type in
                let isSelected = timer.sessionType == type
                Button(action: { timer.selectSession(type) }) {
                    VStack(spacing: 2) {
                        Text(timer.sessionLabel(type))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                        Text("\(timer.sessionMinutes(type)) min")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isSelected ? theme.accentBlue.opacity(0.8) : theme.textMuted)
                    }
                    .foregroundColor(isSelected ? theme.accentBlue : theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? theme.accentBlue.opacity(0.1) : theme.fieldBg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? theme.accentBlue.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(timer.classicState != .idle)
                .opacity(timer.classicState != .idle && !isSelected ? 0.5 : 1)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch timer.classicState {
            case .idle:
                actionBtn("play.fill", "Start", .white, theme.accentBlue) {
                    timer.startClassic()
                }
            case .running:
                actionBtn("pause.fill", "Pause", .white, theme.accentYellow) {
                    timer.pauseClassic()
                }
            case .paused:
                actionBtn("play.fill", "Resume", .white, theme.accentGreen) {
                    timer.resumeClassic()
                }
            }

            actionBtn("arrow.counterclockwise", "Reset", theme.textSecondary, theme.fieldBg) {
                timer.resetClassic()
            }
        }
    }

    private func actionBtn(_ icon: String, _ label: String, _ fg: Color, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .foregroundColor(fg)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(bg)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Block Timer View

private struct BlockTimerView: View {
    @Environment(\.theme) var theme
    @ObservedObject var timer: PomodoroTimer

    private let gridColumns = 5

    var body: some View {
        if timer.showCelebration {
            celebrationOverlay
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: timer.showCelebration)
        } else {
            VStack(spacing: 16) {
                // Heading
                VStack(spacing: 4) {
                    Text("Build momentum.")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.text)

                    Text("\(timer.completedBlocks) of \(timer.blockGoal) blocks today")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.textSecondary)

                    Text("(\(timer.totalBlockMinutes) min total)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textMuted)
                }

                // Grid
                blockGrid

                // Pending prompt
                if timer.pendingBlockIndex != nil {
                    Text("Tap the glowing block to claim it!")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.accentGreen)
                        .padding(.vertical, 4)
                }

                // Countdown when active
                if timer.blockState == .running || timer.blockState == .paused {
                    VStack(spacing: 4) {
                        Text(timer.formatTime(timer.blockTimeRemaining))
                            .font(.system(size: 32, weight: .light, design: .monospaced))
                            .foregroundColor(theme.text)
                            .monospacedDigit()

                        Text("Block \(timer.completedBlocks + 1) of \(timer.blockGoal)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                    }
                    .padding(.vertical, 4)
                }

                // Goal selectors (idle only)
                if timer.blockState == .idle && timer.pendingBlockIndex == nil {
                    goalSelectors
                }

                // Action button (hide when pending)
                if timer.pendingBlockIndex == nil {
                    actionButton
                }

                // Footer
                Text(footerText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMuted)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: timer.showCelebration)
        }
    }

    // MARK: Grid

    private var blockGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: gridColumns),
            spacing: 6
        ) {
            ForEach(0..<timer.blockGoal, id: \.self) { index in
                blockCell(index: index)
            }
        }
        .padding(.vertical, 8)
    }

    private func blockCell(index: Int) -> some View {
        let isCompleted = index < timer.completedBlocks
        let isCurrent = index == timer.completedBlocks && timer.blockState != .idle
        let isPending = timer.pendingBlockIndex == index
        let isNext = index == timer.completedBlocks && timer.blockState == .idle && timer.pendingBlockIndex == nil && !timer.showCelebration
        let isCelebrating = timer.celebrationBlockIndex == index && timer.showCelebration

        return RoundedRectangle(cornerRadius: 6)
            .fill(
                isPending ? theme.accentGreen.opacity(0.25) :
                isCompleted || isCelebrating ? theme.accentBlue.opacity(0.2) :
                theme.fieldBg
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isPending ? theme.accentGreen :
                        isNext ? theme.accentBlue.opacity(0.5) :
                            isCurrent ? theme.accentBlue :
                            isCompleted || isCelebrating ? theme.accentBlue.opacity(0.3) :
                            theme.cardBorder,
                        style: isNext
                            ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                            : StrokeStyle(lineWidth: isPending ? 2 : 1)
                    )
            )
            .overlay(
                Group {
                    if isCompleted || isCelebrating {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(theme.accentBlue)
                    }
                    if isPending {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14))
                            .foregroundColor(theme.accentGreen)
                            .modifier(PulseModifier())
                    }
                    if isCurrent {
                        Circle()
                            .fill(theme.accentBlue)
                            .frame(width: 8, height: 8)
                            .modifier(PulseModifier())
                    }
                }
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(isCelebrating ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isCelebrating)
            .onTapGesture {
                if isPending {
                    timer.claimBlock()
                }
            }
    }

    // MARK: Goal Selectors

    private var goalSelectors: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("Daily Goal (Blocks)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textMuted)

                HStack(spacing: 8) {
                    ForEach([10, 20, 30], id: \.self) { count in
                        pillButton(label: "\(count)", isSelected: timer.blockGoal == count) {
                            timer.setBlockGoal(count)
                        }
                    }
                }
            }

            VStack(spacing: 4) {
                Text("Daily Goal (Hours)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textMuted)

                HStack(spacing: 8) {
                    ForEach([1, 2, 3, 4], id: \.self) { hours in
                        let matchingBlocks = (hours * 60) / timer.blockDuration
                        pillButton(label: "\(hours)h", isSelected: timer.blockGoal == matchingBlocks) {
                            timer.setHoursGoal(hours)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach([5, 10], id: \.self) { minutes in
                    pillButton(label: "\(minutes) min", isSelected: timer.blockDuration == minutes, wide: true) {
                        timer.setBlockDuration(minutes)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func pillButton(label: String, isSelected: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .foregroundColor(isSelected ? .white : theme.textSecondary)
                .padding(.horizontal, wide ? 20 : 14)
                .padding(.vertical, 6)
                .background(isSelected ? theme.accentBlue : theme.fieldBg)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Action Button

    private var actionButton: some View {
        Group {
            switch timer.blockState {
            case .idle:
                let allDone = timer.completedBlocks >= timer.blockGoal
                Button(action: {
                    guard !allDone else { return }
                    timer.dismissCelebration()
                    timer.startBlock()
                }) {
                    Text(allDone ? "Goal Complete!" : "Start \(timer.blockDuration) min")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(allDone ? theme.accentGreen : Color(hex: "1e293b"))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(allDone)

            case .running:
                Button(action: { timer.pauseBlock() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12))
                        Text("Pause")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accentYellow)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

            case .paused:
                HStack(spacing: 8) {
                    Button(action: { timer.resumeBlock() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("Resume")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accentGreen)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Button(action: { timer.resetBlocks() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 18)
                            .background(theme.fieldBg)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Celebration

    private var celebrationOverlay: some View {
        ZStack {
            // Full-screen background
            theme.dropBg
                .ignoresSafeArea()

            // Animated color rings
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(
                        [theme.accentGreen, theme.accentBlue, theme.accentPurple][i].opacity(0.15),
                        lineWidth: 40
                    )
                    .frame(width: CGFloat(120 + i * 100), height: CGFloat(120 + i * 100))
                    .scaleEffect(timer.showCelebration ? 1.0 : 0.3)
                    .opacity(timer.showCelebration ? 1.0 : 0)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.6)
                            .delay(Double(i) * 0.1),
                        value: timer.showCelebration
                    )
            }

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(theme.accentGreen)
                    .scaleEffect(timer.showCelebration ? 1.0 : 0.1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: timer.showCelebration)

                Text(timer.celebrationText)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.text)

                Text("Block \(timer.completedBlocks) of \(timer.blockGoal)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(theme.textSecondary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.fieldBg)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.accentGreen)
                            .frame(
                                width: geo.size.width * CGFloat(timer.completedBlocks) / CGFloat(max(timer.blockGoal, 1)),
                                height: 8
                            )
                            .animation(.spring(response: 0.5), value: timer.completedBlocks)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 40)

                Text("\(timer.completedBlocks * timer.blockDuration) min done today")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMuted)

                Spacer()

                Button(action: { timer.dismissCelebration() }) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accentGreen)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerText: String {
        if timer.completedBlocks >= timer.blockGoal && timer.blockGoal > 0 {
            return "Goal reached! Amazing work today."
        }
        return "Keep going. Keep the momentum going."
    }
}

// MARK: - Pulse Animation

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 0.8)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
