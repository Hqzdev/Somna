//
//  SomnaStore.swift
//  Somna
//
//  The app's data layer on this iPhone:
//  HealthKitReader → HealthCache (normalized samples) → SomnaCore engine
//  → one SomnaSnapshot every screen reads.
//  Person-entered data (questionnaire, settings, check-ins, journal, plan
//  marks, experiments, source order) and nightly summaries live in SwiftData.
//  No account, no network API, no CloudKit.
//
//  AppState keeps navigation and interface state only; formulas live in
//  SomnaCore.
//

import Foundation
import Observation
import SwiftData
import HealthKit

nonisolated enum PlanStepStatus: String, Codable, Sendable {
    case pending, done, skipped
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case failed(String)
}

@Observable
final class SomnaStore {
    // MARK: State read by screens

    private(set) var snapshot: SomnaSnapshot = .empty()
    private(set) var profile: OnboardingProfile = .empty
    private(set) var settings: SleepSettings = .default
    private(set) var goalHistory: [GoalChange] = []
    private(set) var checkIns: [DayKey: MorningCheckIn] = [:]
    private(set) var journal: [String: JournalEntry] = [:]
    private(set) var customFactors: [JournalFactor] = []
    private(set) var experiments: [Experiment] = []
    private(set) var sourcePreferences: [SourcePreference] = []
    /// Marks on tonight's plan, by action id.
    private(set) var planStatuses: [String: PlanStepStatus] = [:]
    private(set) var sync: SyncStatus = .idle
    private(set) var lastSync: Date?
    /// The system Health sheet was shown at least once.
    private(set) var healthRequested = false
    private(set) var hasLoaded = false
    private(set) var usesDemoData = false
    private(set) var alarmMessage: String?

    var isOnboarded: Bool { profile.isCompleted }
    var healthAvailable: Bool { HealthKitReader.isAvailable }
    var today: DayKey { snapshot.today }

    // MARK: Private

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let reader = HealthKitReader()
    @ObservationIgnored private var cache = HealthCache()
    @ObservationIgnored private var observer: HKObserverQuery?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var summariesDirty = false
    @ObservationIgnored private var scheduledWake: Int?
    @ObservationIgnored var onWatchStateChanged: (() -> Void)?

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        loadRecords()
    }

    // MARK: Lifecycle

    /// Loads the cache, computes the first snapshot and syncs with Health.
    func start() async {
        let loaded = await Task.detached(priority: .userInitiated) { HealthCacheFile.load() }.value
        cache = loaded ?? HealthCache()
        summariesDirty = loaded != nil
        lastSync = cache.lastSync
        #if DEBUG
        if usesDemoData { cache = makeDemoCache() }
        #endif
        recompute()
        hasLoaded = true
        if !usesDemoData && healthRequested {
            await refreshHealth()
            startObserving()
        }
    }

    /// Called when the app returns to the foreground.
    func becameActive() async {
        guard hasLoaded else { return }
        if !usesDemoData && healthRequested {
            await refreshHealth()
        } else {
            recompute()
        }
    }

    // MARK: Apple Health

    /// Shows the system permission sheet in context, then syncs.
    func connectHealth() async {
        guard healthAvailable else { return }
        do {
            try await reader.requestAuthorization()
        } catch {
            sync = .failed("Не удалось открыть запрос доступа к Здоровью")
            return
        }
        healthRequested = true
        record.healthRequested = true
        save()
        await refreshHealth()
        startObserving()
    }

    func refreshHealth() async {
        guard healthAvailable, healthRequested, !usesDemoData, sync != .syncing else { return }
        sync = .syncing
        let reader = self.reader
        let current = cache
        let tz = TimeZone.current
        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                try await HealthSync.refresh(current, reader: reader, now: Date(), timeZone: tz)
            }.value
            cache = updated
            lastSync = updated.lastSync
            Task.detached(priority: .utility) { HealthCacheFile.save(updated) }
            sync = .idle
            summariesDirty = true
            recompute()
        } catch {
            sync = .failed("Не удалось прочитать данные Здоровья. Потяните вниз, чтобы повторить.")
        }
    }

    private func startObserving() {
        guard observer == nil, healthAvailable, healthRequested, !usesDemoData else { return }
        observer = reader.observeSleep { [weak self] in
            Task { @MainActor in
                await self?.refreshHealth()
            }
        }
    }

    // MARK: Recompute

    /// Rebuilds the snapshot off the main thread from cache + records.
    func recompute() {
        generation += 1
        let current = generation
        let input = makeInput()
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) { SomnaEngine.compute(input) }.value
            guard current == self.generation else { return }
            self.snapshot = snapshot
            self.afterCompute(snapshot)
        }
    }

    private func makeInput() -> SomnaInput {
        var input = SomnaInput()
        cache.fill(&input)
        input.sourcePreferences = sourcePreferences
        input.profile = profile
        input.settings = settings
        input.checkIns = Array(checkIns.values)
        input.goalHistory = goalHistory
        input.journal = Array(journal.values)
        input.customFactors = customFactors
        input.experiments = experiments
        input.now = Date()
        input.timeZone = .current
        return input
    }

    private func afterCompute(_ snapshot: SomnaSnapshot) {
        if planStatusesDay != snapshot.today {
            loadPlanStatuses(for: snapshot.today)
        }
        if summariesDirty {
            summariesDirty = false
            persistSummaries(snapshot)
        }
        if settings.alarmEnabled, scheduledWake != snapshot.wakeMinutes {
            Task { await scheduleAlarm(minutes: snapshot.wakeMinutes) }
        }
        onWatchStateChanged?()
    }

    // MARK: Questionnaire

    func completeOnboarding(with draft: OnboardingProfile) {
        profile = draft.normalized(completed: true)
        record.profile = profile
        summariesDirty = true
        save()
        recompute()
    }

    func updateProfile(_ edited: OnboardingProfile) {
        profile = edited.normalized(completed: true)
        record.profile = profile
        summariesDirty = true
        save()
        recompute()
    }

    // MARK: Settings

    func setGoal(minutes: Int) {
        settings.goalMinutes = min(11 * 60, max(5 * 60, minutes))
        record.settings = settings
        let day = DayKey(date: Date(), timeZone: .current)
        let key = day.description
        if let existing = fetchOne(GoalChangeRecord.self, #Predicate { $0.day == key }) {
            existing.minutes = settings.goalMinutes
        } else {
            context.insert(GoalChangeRecord(day: key, minutes: settings.goalMinutes))
        }
        goalHistory.removeAll { $0.effectiveDay == day }
        goalHistory.append(GoalChange(effectiveDay: day, minutes: settings.goalMinutes))
        summariesDirty = true
        save()
        recompute()
    }

    func setWake(minutes: Int?) {
        settings.wakeMinutes = minutes
        record.settings = settings
        save()
        recompute()
    }

    func setHaptics(_ enabled: Bool) {
        settings.hapticsEnabled = enabled
        record.settings = settings
        save()
    }

    func setAlarm(enabled: Bool) async {
        alarmMessage = nil
        if enabled {
            await scheduleAlarm(minutes: snapshot.wakeMinutes)
        } else {
            await cancelAlarm()
        }
    }

    /// Saves the wake-up time (nil = the usual wake-up from the data) and the
    /// alarm in one step, so the alarm is scheduled once with the new time.
    func saveWake(minutes: Int?, alarm enabled: Bool) async {
        settings.wakeMinutes = minutes
        record.settings = settings
        save()
        alarmMessage = nil
        if enabled {
            await scheduleAlarm(minutes: minutes ?? snapshot.wakeMinutes)
        } else if settings.alarmEnabled || !record.alarmID.isEmpty {
            await cancelAlarm()
        }
        recompute()
    }

    private func cancelAlarm() async {
        if let id = UUID(uuidString: record.alarmID) { await AlarmScheduler.cancel(id) }
        record.alarmID = ""
        record.alarmMinutes = -1
        settings.alarmEnabled = false
        record.settings = settings
        scheduledWake = nil
        save()
        onWatchStateChanged?()
    }

    private func scheduleAlarm(minutes: Int) async {
        let previous = UUID(uuidString: record.alarmID)
        switch await AlarmScheduler.schedule(minutes: minutes, replacing: previous) {
        case .scheduled(let id):
            record.alarmID = id.uuidString
            record.alarmMinutes = minutes
            settings.alarmEnabled = true
            scheduledWake = minutes
            alarmMessage = nil
        case .denied:
            settings.alarmEnabled = false
            alarmMessage = "Нет разрешения на будильники. Его можно дать в Настройках → Somna."
        case .failed(let message):
            settings.alarmEnabled = false
            alarmMessage = "Будильник не поставлен: \(message)"
        }
        record.settings = settings
        save()
        onWatchStateChanged?()
    }

    // MARK: Morning check-in

    func checkIn(for day: DayKey) -> MorningCheckIn? { checkIns[day] }

    func saveCheckIn(day: DayKey, energy: Int, quality: Int? = nil, tags: [String], note: String) {
        let value = MorningCheckIn(dayKey: day, energy: energy, quality: quality, tags: tags, note: note)
        checkIns[day] = value
        let key = day.description
        if let existing = fetchOne(CheckInRecord.self, #Predicate { $0.day == key }) {
            existing.energy = value.energy
            existing.quality = value.quality
            existing.tags = value.tags
            existing.note = value.note
            existing.updatedAt = Date()
        } else {
            context.insert(CheckInRecord(day: key, energy: value.energy, quality: value.quality, tags: value.tags, note: value.note))
        }
        summariesDirty = true
        save()
        recompute()
    }

    // MARK: Journal

    func journalValue(day: DayKey, factorID: String) -> Double? {
        journal[Self.journalKey(day, factorID)]?.value
    }

    /// nil removes the entry (the factor becomes unknown for that day).
    func setJournal(day: DayKey, factorID: String, value: Double?) {
        let key = Self.journalKey(day, factorID)
        let existing = fetchOne(JournalRecord.self, #Predicate { $0.key == key })
        if let value {
            journal[key] = JournalEntry(dayKey: day, factorID: factorID, value: value)
            if let existing {
                existing.value = value
                existing.updatedAt = Date()
            } else {
                context.insert(JournalRecord(day: day.description, factorID: factorID, value: value))
            }
        } else {
            journal[key] = nil
            if let existing { context.delete(existing) }
        }
        save()
        recompute()
    }

    func addCustomFactor(title: String, kind: FactorKind) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "custom-\(UUID().uuidString.prefix(8))"
        context.insert(CustomFactorRecord(id: id, title: String(trimmed.prefix(40)), kind: kind.rawValue))
        customFactors.append(Self.customFactor(id: id, title: String(trimmed.prefix(40)), kind: kind))
        save()
        recompute()
    }

    func removeCustomFactor(id: String) {
        if let r = fetchOne(CustomFactorRecord.self, #Predicate { $0.id == id }) { context.delete(r) }
        for (key, entry) in journal where entry.factorID == id {
            journal[key] = nil
        }
        let entries = (try? context.fetch(FetchDescriptor<JournalRecord>(predicate: #Predicate { $0.factorID == id }))) ?? []
        entries.forEach(context.delete)
        customFactors.removeAll { $0.id == id }
        save()
        recompute()
    }

    // MARK: Experiments

    var activeExperiment: Experiment? { experiments.first { $0.status == .active } }

    func startExperiment(title: String, detail: String, metric: OutcomeMetric) {
        for e in experiments where e.status == .active { stopExperiment(id: e.id, finished: false) }
        let id = UUID().uuidString
        let start = today
        context.insert(ExperimentRecord(id: id, title: title, detail: detail, metric: metric.rawValue,
                                        startDay: start.description, status: ExperimentStatus.active.rawValue))
        experiments.append(Experiment(id: id, title: title, detail: detail, metric: metric, startDay: start))
        save()
        recompute()
    }

    func setExperimentDone(id: String, day: DayKey, done: Bool) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        var days = Set(experiments[index].doneDays)
        if done { days.insert(day) } else { days.remove(day) }
        experiments[index].doneDays = days.sorted()
        if let r = fetchOne(ExperimentRecord.self, #Predicate { $0.id == id }) {
            r.doneDays = experiments[index].doneDays.map(\.description)
        }
        save()
        recompute()
    }

    func stopExperiment(id: String, finished: Bool) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        let status: ExperimentStatus = finished ? .finished : .stopped
        experiments[index].status = status
        if let r = fetchOne(ExperimentRecord.self, #Predicate { $0.id == id }) { r.status = status.rawValue }
        save()
        recompute()
    }

    // MARK: Sources

    /// New order of sources (first = most trusted).
    func setSourceOrder(_ sources: [DetectedSource]) {
        let existing = (try? context.fetch(FetchDescriptor<SourcePreferenceRecord>())) ?? []
        existing.forEach(context.delete)
        sourcePreferences = sources.enumerated().map { SourcePreference(sourceID: $1.id, name: $1.name, priority: $0) }
        for p in sourcePreferences {
            context.insert(SourcePreferenceRecord(sourceID: p.sourceID, name: p.name, priority: p.priority))
        }
        save()
        summariesDirty = true
        recompute()
    }

    // MARK: Evening plan

    @ObservationIgnored private var planStatusesDay: DayKey?

    func status(of action: PlanAction) -> PlanStepStatus {
        planStatuses[action.id] ?? .pending
    }

    func setStatus(_ status: PlanStepStatus, for action: PlanAction) {
        planStatuses[action.id] = status
        let day = snapshot.plan.dayKey.description
        let actions = (try? JSONEncoder().encode(snapshot.plan.actions)) ?? Data()
        let statuses = (try? JSONEncoder().encode(planStatuses.mapValues(\.rawValue))) ?? Data()
        if let r = fetchOne(PlanRecord.self, #Predicate { $0.day == day }) {
            r.actionsData = actions
            r.statusesData = statuses
            r.updatedAt = Date()
        } else {
            context.insert(PlanRecord(day: day, actionsData: actions, statusesData: statuses))
        }
        save()
        onWatchStateChanged?()
    }

    private func loadPlanStatuses(for day: DayKey) {
        planStatusesDay = day
        let key = day.description
        guard let r = fetchOne(PlanRecord.self, #Predicate { $0.day == key }),
              let raw = try? JSONDecoder().decode([String: String].self, from: r.statusesData) else {
            planStatuses = [:]
            return
        }
        planStatuses = raw.compactMapValues(PlanStepStatus.init(rawValue:))
    }

    // MARK: Delete & export

    /// Removes everything Somna stored on this iPhone. Records in Apple
    /// Health are not touched.
    func deleteAllData() async {
        if let id = UUID(uuidString: record.alarmID) { await AlarmScheduler.cancel(id) }
        if let observer { reader.store.stop(observer) }
        observer = nil
        try? context.delete(model: ProfileRecord.self)
        try? context.delete(model: CheckInRecord.self)
        try? context.delete(model: GoalChangeRecord.self)
        try? context.delete(model: JournalRecord.self)
        try? context.delete(model: CustomFactorRecord.self)
        try? context.delete(model: ExperimentRecord.self)
        try? context.delete(model: SourcePreferenceRecord.self)
        try? context.delete(model: PlanRecord.self)
        try? context.delete(model: NightSummaryRecord.self)
        save()
        HealthCacheFile.delete()
        LegacyProfileFile.delete()
        cache = HealthCache()
        cachedRecord = nil
        profile = .empty
        settings = .default
        goalHistory = []
        checkIns = [:]
        journal = [:]
        customFactors = []
        experiments = []
        sourcePreferences = []
        planStatuses = [:]
        healthRequested = false
        usesDemoData = false
        lastSync = nil
        scheduledWake = nil
        alarmMessage = nil
        sync = .idle
        recompute()
    }

    func exportFiles() throws -> [URL] {
        try DataExporter.export(snapshot: snapshot, profile: profile, settings: settings, goalHistory: goalHistory,
                                checkIns: Array(checkIns.values), journal: Array(journal.values),
                                factors: snapshot.factors, experiments: experiments)
    }

    // MARK: Debug demo data

    #if DEBUG
    /// Fills the pipeline with synthetic nights (Simulator has no sleep data).
    func setDemoData(_ enabled: Bool) {
        usesDemoData = enabled
        record.demoData = enabled
        save()
        if enabled {
            cache = makeDemoCache()
        } else {
            cache = HealthCacheFile.load() ?? HealthCache()
        }
        summariesDirty = true
        recompute()
    }

    private func makeDemoCache() -> HealthCache {
        let yesterdayOrToday = DayKey(date: Date(), timeZone: .current)
        return DemoHealthData.make(nights: 45, lastWakeDay: yesterdayOrToday, timeZone: .current)
    }
    #endif

    // MARK: Records

    @ObservationIgnored private var cachedRecord: ProfileRecord?

    private var record: ProfileRecord {
        if let r = cachedRecord { return r }
        if let existing = try? context.fetch(FetchDescriptor<ProfileRecord>()).first {
            cachedRecord = existing
            return existing
        }
        let created = ProfileRecord()
        context.insert(created)
        cachedRecord = created
        return created
    }

    private func loadRecords() {
        LegacyProfileFile.migrate(into: record)
        profile = record.profile
        settings = record.settings
        let storedGoals = (try? context.fetch(FetchDescriptor<GoalChangeRecord>())) ?? []
        if storedGoals.isEmpty {
            let initial = GoalChangeRecord(day: "1900-01-01", minutes: settings.goalMinutes)
            context.insert(initial)
            goalHistory = [GoalChange(effectiveDay: DayKey(string: initial.day)!, minutes: initial.minutes)]
        } else {
            goalHistory = storedGoals.compactMap { r in
                DayKey(string: r.day).map { GoalChange(effectiveDay: $0, minutes: r.minutes) }
            }.sorted { $0.effectiveDay < $1.effectiveDay }
        }
        healthRequested = record.healthRequested
        scheduledWake = record.alarmMinutes >= 0 ? record.alarmMinutes : nil
        #if DEBUG
        usesDemoData = record.demoData
        #endif

        for r in (try? context.fetch(FetchDescriptor<CheckInRecord>())) ?? [] {
            guard let day = DayKey(string: r.day) else { continue }
            checkIns[day] = MorningCheckIn(dayKey: day, energy: r.energy, quality: r.quality, tags: r.tags, note: r.note)
        }
        for r in (try? context.fetch(FetchDescriptor<JournalRecord>())) ?? [] {
            guard let day = DayKey(string: r.day) else { continue }
            journal[r.key] = JournalEntry(dayKey: day, factorID: r.factorID, value: r.value)
        }
        customFactors = ((try? context.fetch(FetchDescriptor<CustomFactorRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .map { Self.customFactor(id: $0.id, title: $0.title, kind: FactorKind(rawValue: $0.kind) ?? .yesNo) }
        experiments = ((try? context.fetch(FetchDescriptor<ExperimentRecord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .compactMap { r in
                guard let start = DayKey(string: r.startDay) else { return nil }
                return Experiment(id: r.id, title: r.title, detail: r.detail,
                                  metric: OutcomeMetric(rawValue: r.metric) ?? .score,
                                  startDay: start,
                                  status: ExperimentStatus(rawValue: r.status) ?? .stopped,
                                  doneDays: r.doneDays.compactMap(DayKey.init(string:)))
            }
        sourcePreferences = ((try? context.fetch(FetchDescriptor<SourcePreferenceRecord>(sortBy: [SortDescriptor(\.priority)]))) ?? [])
            .map { SourcePreference(sourceID: $0.sourceID, name: $0.name, priority: $0.priority) }
        save()
    }

    private func persistSummaries(_ snapshot: SomnaSnapshot) {
        let existing = (try? context.fetch(FetchDescriptor<NightSummaryRecord>())) ?? []
        var byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for report in snapshot.reports {
            let key = report.dayKey.description
            if let r = byDay.removeValue(forKey: key) {
                r.update(from: report)
            } else {
                context.insert(NightSummaryRecord(report: report))
            }
        }
        // Nights no longer in Health (deleted there) disappear here too.
        for stale in byDay.values { context.delete(stale) }
        save()
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        try? context.save()
    }

    static func journalKey(_ day: DayKey, _ factorID: String) -> String {
        "\(day.description)|\(factorID)"
    }

    static func customFactor(id: String, title: String, kind: FactorKind) -> JournalFactor {
        JournalFactor(id: id, title: title, kind: kind, systemImage: "tag", section: .day,
                      threshold: kind == .scale ? 4 : 1, avoidable: kind != .scale, isCustom: true)
    }
}

/// The questionnaire used to live in a JSON file before SwiftData.
enum LegacyProfileFile {
    static var url: URL {
        URL.applicationSupportDirectory
            .appending(path: "Somna", directoryHint: .isDirectory)
            .appending(path: "profile.json", directoryHint: .notDirectory)
    }

    static func migrate(into record: ProfileRecord) {
        guard let data = try? Data(contentsOf: url),
              let old = try? JSONDecoder().decode(OnboardingProfile.self, from: data) else { return }
        if !record.isCompleted {
            record.profile = old
        }
        delete()
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
