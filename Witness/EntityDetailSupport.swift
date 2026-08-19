import SwiftUI

// MARK: - Opaque JSONValue accessors (read `attributes` defensively; never dump the blob)
extension JSONValue {
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var intValue: Int? {
        switch self {
        case .number(let d): return Int(d)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    subscript(_ key: String) -> JSONValue? { objectValue?[key] }

    /// Human display for a SCALAR (nil for empty / arrays / objects). bool→Yes/No, number→trimmed, string→trimmed.
    var displayString: String? {
        switch self {
        case .string(let s): let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "Yes" : "No"
        case .array, .object, .null: return nil
        }
    }
    /// [String] for a string array attribute (skips empties). nil when not an array.
    var stringArray: [String]? {
        guard let a = arrayValue else { return nil }
        return a.compactMap { $0.displayString }
    }
}

// MARK: - Value formatter primitive (Phases 2–5)
enum EDFormat {
    /// bool/number/string → a display string; nil for empty or containers.
    static func value(_ v: JSONValue?) -> String? { v?.displayString }
}

// MARK: - Reusable detail primitives (Phases 2–5)

/// Collapsible titled card with an optional count badge. Collapsed by default unless `defaultExpanded`.
struct EDSection<Content: View>: View {
    let title: String
    var count: Int? = nil
    @State private var expanded: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, count: Int? = nil, defaultExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.count = count; self.content = content
        _expanded = State(initialValue: defaultExpanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.3).foregroundStyle(WV.gold)
                    if let count {
                        Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.55))
                            .padding(.horizontal, 7).padding(.vertical, 2).background(WT.ink.opacity(0.06), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.4))
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded { content() }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }
}

struct EDPill: View {
    let text: String
    var icon: String? = nil
    var tone: Color = WV.teal
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tone) }
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.75)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(tone.opacity(0.10), in: Capsule())
    }
}

/// [String] → wrapping pills; empties skipped, whole thing hidden when nothing remains.
struct EDPillWrap: View {
    let values: [String]
    var body: some View {
        let vals = values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !vals.isEmpty {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(vals.enumerated()), id: \.offset) { _, v in EDPill(text: v) }
            }
        }
    }
}

/// Label + value; renders NOTHING when the value is empty.
struct EDFieldRow: View {
    let label: String
    let value: String?
    init(label: String, value: String?) { self.label = label; self.value = value }
    init(_ label: String, _ value: JSONValue?) { self.label = label; self.value = EDFormat.value(value) }
    var body: some View {
        if let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
                Text(v).font(.system(size: 15)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}

/// One verbatim line of dialogue parsed from attributes.dialogue_spoken.
struct DialogueLine: Identifiable {
    let id = UUID()
    let quote: String
    let memoryId: String?
    let responderId: String?
    let scene: Int?
    let order: Int?
}

/// One per-memory people-detail record from attributes.people_details_by_memory (dict value or array element).
struct PersonMemoryDetail: Identifiable {
    let id = UUID()
    let memoryId: String?
    let obj: [String: JSONValue]
}

/// A single hero card spec (best-pick surfaces at the top of the page).
struct EDHero: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let memoryId: String?
    var quoted: Bool = false
}

// MARK: - Phase 5 declarative section engine

enum EDFieldKind { case text, entity, entityArray }

struct EDField: Identifiable {
    let key: String
    let label: String
    var kind: EDFieldKind = .text
    var id: String { key }
}

struct EDPillSpec {
    let key: String
    var icon: String? = nil
    var tone: Color = WV.teal
    var resolveEntity: Bool = false     // value is an entity UUID → resolve or omit
    var prefix: String = ""
}

/// Declarative section: lead text (quote = italic, plain = serif), a pills row, then field rows. Rendered over
/// records(key); empty records → the section is omitted entirely.
struct AttrSectionSpec: Identifiable {
    let title: String
    let key: String
    var quoteKeys: [String] = []        // first non-empty → italic “quote”
    var leadKeys: [String] = []         // first non-empty → serif body
    var pills: [EDPillSpec] = []
    var fields: [EDField] = []
    var id: String { key }
}

struct EDPillData: Identifiable { let id = UUID(); let text: String; let icon: String?; let tone: Color }
