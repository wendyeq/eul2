//
//  QuotaStore.swift
//  eul
//

import Combine
import Foundation

class QuotaStore: ObservableObject {
    static let allowedRefreshMinutes = [1, 2, 5, 15]
    private static let idleStopInterval: TimeInterval = 5 * 60

    @Published private(set) var cursor = QuotaProviderSnapshot.pending
    @Published private(set) var grok = QuotaProviderSnapshot.pending
    @Published private(set) var codex = QuotaProviderSnapshot.pending

    private var repeatingTimer: Timer?
    private var idleStopTimer: Timer?
    private var isFetching = false
    private var isSleeping = false
    private var wasWatching = false
    private var lastShowCursor = true
    private var lastShowGrok = true
    private var lastShowCodex = true
    private var lastTimerMinutes: Int?
    private var cancellables = Set<AnyCancellable>()

    init() {
        bind()
    }

    func pause() {
        isSleeping = true
        stopTimers()
    }

    func resume() {
        isSleeping = false
        handleStateChange(forceFetchIfWatching: true)
    }

    private func bind() {
        let watchingInputs = Publishers.CombineLatest4(
            SharedStore.ui.$menuOpened,
            SharedStore.ui.$isStatusMenuPinned,
            SharedStore.preference.$quotaRefreshRate,
            SharedStore.menuComponents.$activeComponents
        )
        let providerToggles = Publishers.CombineLatest3(
            SharedStore.preference.$showCursorQuota,
            SharedStore.preference.$showGrokQuota,
            SharedStore.preference.$showCodexQuota
        )
        watchingInputs.combineLatest(providerToggles)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.handleStateChange(forceFetchIfWatching: false)
            }
            .store(in: &cancellables)
    }

    private func isWatching() -> Bool {
        guard SharedStore.menuComponents.activeComponents.contains(.Quota) else {
            return false
        }
        return SharedStore.ui.menuOpened || SharedStore.ui.isStatusMenuPinned
    }

    private func handleStateChange(forceFetchIfWatching: Bool) {
        guard !isSleeping else {
            stopTimers()
            wasWatching = false
            return
        }

        let watching = isWatching()
        let showCursor = SharedStore.preference.showCursorQuota
        let showGrok = SharedStore.preference.showGrokQuota
        let showCodex = SharedStore.preference.showCodexQuota
        let enabledNewProvider = (showCursor && !lastShowCursor)
            || (showGrok && !lastShowGrok)
            || (showCodex && !lastShowCodex)
        lastShowCursor = showCursor
        lastShowGrok = showGrok
        lastShowCodex = showCodex
        if watching {
            idleStopTimer?.invalidate()
            idleStopTimer = nil
            if repeatingTimer == nil || !wasWatching || lastTimerMinutes != SharedStore.preference.quotaRefreshRate {
                startRepeatingTimer()
            }
            if !wasWatching || forceFetchIfWatching || enabledNewProvider {
                refresh()
            }
        } else if wasWatching {
            scheduleIdleStop()
        } else if !SharedStore.menuComponents.activeComponents.contains(.Quota) {
            stopTimers()
        }
        wasWatching = watching
    }

    private func startRepeatingTimer() {
        repeatingTimer?.invalidate()
        let minutes = SharedStore.preference.quotaRefreshRate
        lastTimerMinutes = minutes
        let interval = TimeInterval(max(1, minutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatingTimer = timer
    }

    private func scheduleIdleStop() {
        idleStopTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idleStopInterval, repeats: false) { [weak self] _ in
            self?.repeatingTimer?.invalidate()
            self?.repeatingTimer = nil
            self?.idleStopTimer = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        idleStopTimer = timer
    }

    private func stopTimers() {
        repeatingTimer?.invalidate()
        repeatingTimer = nil
        idleStopTimer?.invalidate()
        idleStopTimer = nil
        lastTimerMinutes = nil
    }

    private func refresh() {
        guard !isFetching else {
            return
        }
        let showCursor = SharedStore.preference.showCursorQuota
        let showGrok = SharedStore.preference.showGrokQuota
        let showCodex = SharedStore.preference.showCodexQuota
        guard showCursor || showGrok || showCodex else {
            return
        }
        isFetching = true
        let group = DispatchGroup()
        if showCursor {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let snapshot = CursorQuotaClient.fetchSync()
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self else {
                        return
                    }
                    self.cursor = QuotaProviderSnapshot.merging(previous: self.cursor, incoming: snapshot)
                }
            }
        }
        if showGrok {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let snapshot = GrokQuotaClient.fetchSync()
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self else {
                        return
                    }
                    self.grok = QuotaProviderSnapshot.merging(previous: self.grok, incoming: snapshot)
                }
            }
        }
        if showCodex {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let snapshot = CodexQuotaClient.fetchSync()
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self else {
                        return
                    }
                    self.codex = QuotaProviderSnapshot.merging(previous: self.codex, incoming: snapshot)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isFetching = false
        }
    }
}
