import SwiftUI

// MARK: - Home's activation engine: cycles the floating prompt, retires kinds after 2, and
// evolves singular prompts to their repeat phrasing once used. All state is LOCAL (UserDefaults):
// there's no backend for this in v1. The view owns the animation/haptics; this owns the "which
// prompt, in what phrasing" decision and the slow cross-fade cadence.
@MainActor
final class HomeActivationViewModel: ObservableObject {
    /// The prompt currently on screen. The view keys its cross-fade off `current?.id`.
    @Published private(set) var current: ActivationPrompt?

    /// Seconds between cross-fades. Slow on purpose — this is ambient, not a slideshow.
    private let cycleInterval: UInt64 = 8_000_000_000   // 8s

    // Local persistence — per-kind recorded counts and the set of singulars already used.
    private let countsKey = "witness.activation.kindCounts"
    private let usedKey = "witness.activation.usedSingulars"
    private var counts: [String: Int]
    private var used: Set<String>

    private var order: [ActivationPrompt] = []
    private var index = 0
    private var cycleTask: Task<Void, Never>?

    init() {
        let store = UserDefaults.standard
        counts = (store.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
        used = Set(store.stringArray(forKey: usedKey) ?? [])
    }

    /// Text to display for `current`, honouring the singular → repeatVariant evolution.
    var currentText: String {
        guard let p = current else { return "" }
        if p.form == .singular, used.contains(p.id), let variant = p.repeatVariant {
            return variant
        }
        return p.text
    }

    // MARK: Lifecycle (called from HomeView .task / .onDisappear)
    func start() {
        rebuild()
        if current == nil || !isActive(current!) {
            index = 0
            current = order.first
        }
        startTicking()
    }

    func stop() {
        cycleTask?.cancel()
        cycleTask = nil
    }

    // MARK: Cycling
    private func startTicking() {
        guard cycleTask == nil else { return }
        cycleTask = Task { [weak self] in
            guard let interval = self?.cycleInterval else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                self?.advance()
            }
        }
    }

    private func advance() {
        guard order.count > 1 else { return }   // nothing to cross-fade to
        index = (index + 1) % order.count
        current = order[index]
    }

    // MARK: Recording feedback (called by HomeView.onSaved with the prompt that seeded the record)
    func didRecord(fromPromptID id: String?) {
        guard let id, let p = ActivationPrompts.all.first(where: { $0.id == id }) else { return }
        if p.form == .singular {
            used.insert(p.id)
            UserDefaults.standard.set(Array(used), forKey: usedKey)
        }
        if p.form != .parent {                          // parents ("You decide…") never count toward retirement
            counts[p.kind, default: 0] += 1
            UserDefaults.standard.set(counts, forKey: countsKey)
        }
        rebuild()
        if let cur = current, !isActive(cur) {          // the prompt we just used may now be retired
            index = 0
            current = order.first
        }
    }

    // MARK: Active set
    private func rebuild() {
        order = ActivationPrompts.all.filter(isActive)
        if index >= order.count { index = 0 }
    }

    /// Parents are evergreen; everything else retires once its kind reaches 2 recorded memories.
    private func isActive(_ p: ActivationPrompt) -> Bool {
        if p.form == .parent { return true }
        return (counts[p.kind] ?? 0) < 2
    }
}
