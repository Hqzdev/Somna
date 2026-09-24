import SwiftUI

private enum WatchStyle {
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.23)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.36)
    static let accent = Color(red: 0.64, green: 0.69, blue: 1.00)
    static let sunrise = Color(red: 1.00, green: 0.56, blue: 0.40)
}

private enum WatchRoute: Hashable {
    case sleep, plan, alarm
}

struct WatchRootView: View {
    @ObservedObject var connection: WatchConnection
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SOMNA")
                        .font(.caption2.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(WatchStyle.accent)

                    if connection.snapshot.hasRecentSleep(at: Date()) {
                        sleepSummary
                    } else {
                        Text("Ждём данные о сне")
                            .font(.headline)
                        Text("Откройте Somna на iPhone после сна")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if connection.snapshot.isStale(at: Date()) {
                        Label("Данные могут устареть", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(WatchStyle.sunrise)
                    }

                    NavigationLink(value: WatchRoute.sleep) {
                        Label("Разбор ночи", systemImage: "moon.stars")
                    }
                    NavigationLink(value: WatchRoute.plan) {
                        Label("План на вечер", systemImage: "bed.double")
                    }
                    NavigationLink(value: WatchRoute.alarm) {
                        Label("Подъём · \(WatchSnapshot.clock(connection.snapshot.wakeMinutes))", systemImage: "alarm")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .navigationTitle("Сегодня")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .sleep: WatchNightView(snapshot: connection.snapshot)
                case .plan: WatchPlanView(snapshot: connection.snapshot)
                case .alarm: WatchAlarmView(connection: connection)
                }
            }
        }
        .tint(WatchStyle.accent)
        .background(WatchStyle.ink)
        .onOpenURL { url in
            switch url.host {
            case "sleep": path = [.sleep]
            case "plan": path = [.plan]
            case "alarm": path = [.alarm]
            default: break
            }
        }
    }

    private var sleepSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let score = connection.snapshot.sleepScore {
                Text("\(score)")
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchStyle.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Прошлая ночь")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let minutes = connection.snapshot.sleepMinutes {
                    Text(WatchSnapshot.duration(minutes))
                        .font(.headline)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct WatchNightView: View {
    let snapshot: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if snapshot.hasRecentSleep(at: Date()), let minutes = snapshot.sleepMinutes {
                    if let score = snapshot.sleepScore {
                        metric("Оценка сна", value: "\(score)", tint: WatchStyle.accent)
                    }
                    metric("Сон", value: WatchSnapshot.duration(minutes), tint: .white)
                    if let deep = snapshot.deepMinutes {
                        metric("Глубокий", value: WatchSnapshot.duration(deep), tint: WatchStyle.accent)
                    }
                    if let rem = snapshot.remMinutes {
                        metric("REM", value: WatchSnapshot.duration(rem), tint: .cyan)
                    }
                } else {
                    Text("Данных за последнюю ночь пока нет")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Сон")
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint)
        }
    }
}

private struct WatchPlanView: View {
    let snapshot: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Сегодня лечь")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(WatchSnapshot.clock(snapshot.bedtimeMinutes))
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchStyle.accent)
                Text("Цель: \(WatchSnapshot.duration(snapshot.goalMinutes)) сна")
                    .font(.footnote)
                if let action = snapshot.planAction {
                    Label(action, systemImage: "sparkle")
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WatchStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Вечер")
    }
}

private struct WatchAlarmView: View {
    @ObservedObject var connection: WatchConnection
    @State private var wakeMinutes = 7 * 60 + 30
    @State private var alarmEnabled = false

    private let wakeOptions = Array(stride(from: 4 * 60, through: 11 * 60 + 30, by: 5))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Подъём", selection: $wakeMinutes) {
                    ForEach(wakeOptions, id: \.self) { minutes in
                        Text(WatchSnapshot.clock(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 86)

                Toggle("Будильник", isOn: $alarmEnabled)

                Button("Сохранить") {
                    connection.saveWake(minutes: wakeMinutes, alarmEnabled: alarmEnabled)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connection.isConnected || connection.isSaving)

                if connection.isSaving {
                    ProgressView("Сохраняем на iPhone")
                } else if let message = connection.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(WatchStyle.sunrise)
                } else if !connection.isConnected {
                    Text("Подключите iPhone, чтобы изменить будильник")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Сигнал создаётся на iPhone и приходит на часы")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Подъём")
        .onAppear(perform: load)
        .onChange(of: connection.snapshot) { _, _ in load() }
    }

    private func load() {
        wakeMinutes = connection.snapshot.wakeMinutes
        alarmEnabled = connection.snapshot.alarmEnabled
    }
}
