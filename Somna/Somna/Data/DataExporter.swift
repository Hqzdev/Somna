//
//  DataExporter.swift
//  Somna
//
//  «Экспорт данных»: CSV files the person can share (for themselves or a
//  doctor) — nights with the computed results, journal, check-ins, plus the
//  questionnaire and settings as JSON. Written to a temporary folder;
//  nothing is sent anywhere by the app.
//

import Foundation

enum DataExporter {
    static func export(snapshot: SomnaSnapshot,
                       profile: OnboardingProfile,
                       settings: SleepSettings,
                       goalHistory: [GoalChange],
                       checkIns: [MorningCheckIn],
                       journal: [JournalEntry],
                       factors: [JournalFactor],
                       experiments: [Experiment]) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Somna-export-\(snapshot.today.description)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let time = DateFormatter()
        time.locale = Locale(identifier: "ru_RU")
        time.dateFormat = "yyyy-MM-dd HH:mm"

        func num(_ v: Double?, _ digits: Int = 0) -> String {
            guard let v else { return "" }
            return String(format: "%.\(digits)f", v)
        }

        var nights = ["ночь (день пробуждения);начало сна;конец сна;сон, мин;бодрствование, мин;в кровати, мин;эффективность, %;засыпание, мин;неизвестно, мин;покрытие стадиями, %;глубокий, мин;REM, мин;основной, мин;оценка;достаточность;непрерывность;ритм;статус сна;статус времени в кровати;статус засыпания;статус ночного бодрствования;почему нет оценки;статус восстановления;ВСР, мс;пульс в покое;источник сна;обновление Health;версия формул"]
        for r in snapshot.reports {
            let n = r.night
            time.timeZone = n.timeZone
            nights.append([
                n.dayKey.description,
                time.string(from: n.sleepStart),
                time.string(from: n.sleepEnd),
                num(n.asleepMinutes),
                num(n.awake / 60),
                num(n.timeInBed.map { $0 / 60 }),
                num(n.efficiency.map { $0 * 100 }),
                num(n.latencyMinutes),
                num(n.unknownMinutes),
                num(r.measurements.detailedStageCoverage.value.map { $0 * 100 }),
                num(n.stages.deep / 60),
                num(n.stages.rem / 60),
                num(n.stages.core / 60),
                r.score.map { "\($0.value)" } ?? "",
                num(r.scoreComponents.duration),
                num(r.scoreComponents.continuity),
                num(r.scoreComponents.regularity),
                r.measurements.asleep.status.rawValue,
                r.measurements.timeInBed.status.rawValue,
                r.measurements.latency.status.rawValue,
                r.measurements.wakeAfterOnset.status.rawValue,
                csv(r.score == nil ? (r.explanation ?? "") : ""),
                csv(r.recovery?.status.title ?? ""),
                num(r.vitals.hrv, 1),
                num(r.vitals.restingHeartRate, 1),
                n.primarySourceID ?? "",
                r.measurements.asleep.refreshedAt.map { time.string(from: $0) } ?? "",
                SomnaSnapshot.formulaVersion
            ].joined(separator: ";"))
        }

        let titles = Dictionary(factors.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        var journalRows = ["день;фактор;значение"]
        for e in journal.sorted(by: { ($0.dayKey, $0.factorID) < ($1.dayKey, $1.factorID) }) {
            journalRows.append("\(e.dayKey);\(csv(titles[e.factorID] ?? e.factorID));\(num(e.value, 1))")
        }

        var checkInRows = ["день;энергия 1–5;как спали 1–5;метки;заметка"]
        for c in checkIns.sorted(by: { $0.dayKey < $1.dayKey }) {
            checkInRows.append("\(c.dayKey);\(c.energy);\(c.quality.map(String.init) ?? "");\(csv(c.tags.joined(separator: ", ")));\(csv(c.note))")
        }

        var experimentRows = ["эксперимент;начало;метрика;статус;отмечено дней"]
        for e in experiments {
            experimentRows.append("\(csv(e.title));\(e.startDay);\(e.metric.title);\(e.status.rawValue);\(e.doneDays.count)")
        }

        struct About: Encodable {
            var profile: OnboardingProfile
            var goalMinutes: Int
            var wakeMinutes: Int?
            var formulaVersion: String
            var note: String
        }
        let about = About(profile: profile, goalMinutes: settings.goalMinutes, wakeMinutes: settings.wakeMinutes,
                          formulaVersion: SomnaSnapshot.formulaVersion,
                          note: "Оценки Somna — объяснимые эвристики, не медицинское заключение.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let goalRows = ["день начала;цель, мин"] + goalHistory.sorted { $0.effectiveDay < $1.effectiveDay }
            .map { "\($0.effectiveDay);\($0.minutes)" }

        let files: [(String, Data)] = [
            ("nights.csv", Data(("\u{FEFF}" + nights.joined(separator: "\n")).utf8)),
            ("journal.csv", Data(("\u{FEFF}" + journalRows.joined(separator: "\n")).utf8)),
            ("checkins.csv", Data(("\u{FEFF}" + checkInRows.joined(separator: "\n")).utf8)),
            ("goal-history.csv", Data(("\u{FEFF}" + goalRows.joined(separator: "\n")).utf8)),
            ("experiments.csv", Data(("\u{FEFF}" + experimentRows.joined(separator: "\n")).utf8)),
            ("profile.json", try encoder.encode(about))
        ]
        var urls: [URL] = []
        for (name, data) in files {
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            urls.append(url)
        }
        return urls
    }

    /// Semicolon CSV: quote fields that contain separators or quotes.
    private static func csv(_ text: String) -> String {
        guard text.contains(";") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
