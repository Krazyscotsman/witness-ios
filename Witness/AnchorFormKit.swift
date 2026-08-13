import SwiftUI

// Shared read/edit form building blocks (used by the relationship + location editors).

func anchorFormSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(WV.gold)
        VStack(spacing: 12) { content() }
    }
}

func anchorFieldLabel(_ label: String, required: Bool = false) -> some View {
    HStack(spacing: 4) {
        Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
        if required { Text("*").font(.system(size: 13, weight: .bold)).foregroundStyle(WV.danger) }
    }
}

func anchorTextField(_ label: String, _ binding: Binding<String>, required: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label, required: required)
        TextField(label, text: binding).font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            .textInputAutocapitalization(.words)
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}

func anchorMultiField(_ label: String, _ binding: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label)
        TextField(label, text: binding, axis: .vertical).lineLimit(3...8)
            .font(.serif(16)).foregroundStyle(WT.ink).tint(WV.teal).textInputAutocapitalization(.sentences)
            .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}

func anchorSelectField(_ label: String, _ options: [String], _ binding: Binding<String>, required: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label, required: required)
        Menu {
            if !required { Button("— None —") { binding.wrappedValue = "" } }
            ForEach(options, id: \.self) { opt in Button(opt) { binding.wrappedValue = opt } }
        } label: {
            HStack {
                Text(binding.wrappedValue.isEmpty ? "Select" : binding.wrappedValue)
                    .font(.system(size: 16)).foregroundStyle(binding.wrappedValue.isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            }
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }
}

/// Stateless date row — the owning form supplies the tap/clear actions and hosts the AnchorDateSheet.
func anchorDateField(_ label: String, _ value: Date?, onEdit: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        anchorFieldLabel(label)
        HStack {
            Button(action: onEdit) {
                HStack {
                    Text(value.map { RelSanitize.iso.string(from: $0) } ?? "Add date")
                        .font(.system(size: 16)).foregroundStyle(value == nil ? WT.ink.opacity(0.4) : WT.ink)
                    Spacer()
                    Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(WV.teal)
                }
            }.buttonStyle(.plain)
            if value != nil {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3)) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }
}

func anchorToggleField(_ label: String, _ binding: Binding<Bool>) -> some View {
    Toggle(isOn: binding) { Text(label).font(.system(size: 15)).foregroundStyle(WT.ink) }
        .tint(WV.teal)
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
}

// Reusable date-picker sheet with a floor date (shared by both editors).
struct AnchorDateSheet: View {
    let initial: Date
    let floor: Date
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: Date, floor: Date, onDone: @escaping (Date) -> Void) {
        self.initial = initial; self.floor = floor; self.onDone = onDone
        _date = State(initialValue: max(initial, floor))
    }
    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            DatePicker("", selection: $date, in: floor...Date(), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
            Button { onDone(date); dismiss() } label: {
                Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment).presentationDetents([.height(420)])
    }
}
