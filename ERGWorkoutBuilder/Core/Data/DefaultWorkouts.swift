import Foundation

enum DefaultWorkouts {
    // MARK: - Zone 2 Endurance (60 min)
    // Warmup: 15 min ramp 40% → 55% FTP
    // Main: 40 min steady at 65% FTP
    // Cooldown: 5 min ramp 65% → 40% FTP
    static func zone2Endurance() -> Workout {
        Workout(
            name: "Zone 2 Endurance",
            notes: "Low intensity aerobic base building",
            steps: [
                .ramp(durationSec: 15 * 60, startPct: 40, endPct: 55),
                .steady(durationSec: 40 * 60, intensityPct: 65),
                .ramp(durationSec: 5 * 60, startPct: 65, endPct: 40)
            ]
        )
    }

    // MARK: - Sweet Spot (60 min)
    // Warmup: 15 min ramp 40% → 75% FTP
    // Main: 2x (15 min at 90% FTP + 5 min at 55% FTP)
    // Cooldown: 5 min ramp 55% → 40% FTP
    static func sweetSpot() -> Workout {
        Workout(
            name: "Sweet Spot",
            notes: "High aerobic work just below threshold",
            steps: [
                .ramp(durationSec: 15 * 60, startPct: 40, endPct: 75),
                .repeats(count: 2, children: [
                    .steady(durationSec: 15 * 60, intensityPct: 90),
                    .steady(durationSec: 5 * 60, intensityPct: 55)
                ]),
                .ramp(durationSec: 5 * 60, startPct: 55, endPct: 40)
            ]
        )
    }

    // MARK: - Over Unders (52 min)
    // Warmup: 10 min ramp 40% → 75% FTP
    // Spin-ups: 2x (30s at 110% + 30s at 50%)
    // Main: 3 sets of 5x (1 min at 105% + 1 min at 90%), 3 min recovery between sets
    // Cooldown: 5 min ramp 55% → 40% FTP
    static func overUnders() -> Workout {
        Workout(
            name: "Over Unders",
            notes: "Threshold intervals alternating above and below FTP",
            steps: [
                // Warmup
                .ramp(durationSec: 10 * 60, startPct: 40, endPct: 75),
                // Spin-ups
                .repeats(count: 2, children: [
                    .steady(durationSec: 30, intensityPct: 110),
                    .steady(durationSec: 30, intensityPct: 50)
                ]),
                // Set 1: 5x (1 min over + 1 min under)
                .repeats(count: 5, children: [
                    .steady(durationSec: 60, intensityPct: 105),
                    .steady(durationSec: 60, intensityPct: 90)
                ]),
                // Recovery
                .steady(durationSec: 3 * 60, intensityPct: 55),
                // Set 2: 5x (1 min over + 1 min under)
                .repeats(count: 5, children: [
                    .steady(durationSec: 60, intensityPct: 105),
                    .steady(durationSec: 60, intensityPct: 90)
                ]),
                // Recovery
                .steady(durationSec: 3 * 60, intensityPct: 55),
                // Set 3: 5x (1 min over + 1 min under)
                .repeats(count: 5, children: [
                    .steady(durationSec: 60, intensityPct: 105),
                    .steady(durationSec: 60, intensityPct: 90)
                ]),
                // Cooldown
                .ramp(durationSec: 5 * 60, startPct: 55, endPct: 40)
            ]
        )
    }

    // MARK: - The Wringer (~44 min) - Based on Zwift's The Wringer
    // Warmup: 8 min ramp 30% → 100% FTP
    // Main: 12x 30s at 205% with progressively shorter recovery (2:40 → 1:50 @ 50%)
    // Cooldown: 5 min ramp 70% → 30% FTP
    static func theWringer() -> Workout {
        Workout(
            name: "The Wringer",
            notes: "Brutal VO2max intervals with shrinking recovery",
            steps: [
                // Warmup
                .ramp(durationSec: 8 * 60, startPct: 30, endPct: 100),
                // 12 intervals with decreasing recovery (160s down to 110s, -5s each)
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 160, intensityPct: 50),  // 2:40
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 155, intensityPct: 50),  // 2:35
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 150, intensityPct: 50),  // 2:30
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 145, intensityPct: 50),  // 2:25
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 140, intensityPct: 50),  // 2:20
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 135, intensityPct: 50),  // 2:15
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 130, intensityPct: 50),  // 2:10
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 125, intensityPct: 50),  // 2:05
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 120, intensityPct: 50),  // 2:00
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 115, intensityPct: 50),  // 1:55
                .steady(durationSec: 30, intensityPct: 200),
                .steady(durationSec: 110, intensityPct: 50),  // 1:50
                .steady(durationSec: 30, intensityPct: 200),
                // Cooldown
                .ramp(durationSec: 5 * 60, startPct: 70, endPct: 30)
            ]
        )
    }

    // MARK: - Zone 2 HR (60 min) - Heart rate controlled
    // Warmup: 10 min ramp 40% → 60% FTP
    // Main: 45 min HR-controlled targeting Zone 2 (adjustable 120-140 bpm default)
    // Cooldown: 5 min ramp down
    static func zone2HR() -> Workout {
        Workout(
            name: "Zone 2 HR",
            notes: "Heart rate controlled endurance - power adjusts to maintain target HR",
            steps: [
                // Warmup
                .ramp(durationSec: 10 * 60, startPct: 40, endPct: 60),
                // Main set - HR controlled
                .hrTarget(durationSec: 45 * 60, lowBpm: 120, highBpm: 140, fallbackPct: 65),
                // Cooldown
                .ramp(durationSec: 5 * 60, startPct: 60, endPct: 40)
            ]
        )
    }

    static var all: [Workout] {
        [zone2Endurance(), sweetSpot(), overUnders(), theWringer(), zone2HR()]
    }
}
