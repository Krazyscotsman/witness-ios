import SwiftUI

// MARK: - Anchors dashboard ("Truth Registry") + search + category list, detail, form, critical people.
struct AnchorsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AnchorStore()
    @State private var searchText = ""

    private var searching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerBlock
                    searchBar
                    if searching {
                        searchResultsView
                    } else {
                        statsRow
                        NavigationLink { CriticalPeopleView(store: store) } label: { criticalCard }
                            .witnessPress(scale: 0.98)
                        ForEach(AnchorCategory.all) { c in
                            NavigationLink { AnchorCategoryView(category: c, store: store) } label: { categoryCard(c) }
                                .witnessPress()
                        }
                        howItWorks
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar(title: "Insights")
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func navBar(title: String) -> some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text(title).font(.system(size: 16))
                }
                .foregroundStyle(WV.teal).frame(height: 44)
            }
            .witnessPress()
            Spacer()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRUTH REGISTRY").font(.system(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(WV.gold)
            Text(searching ? "Choose the anchor to review." : "Truths That Anchor a Life")
                .font(.serif(28)).foregroundStyle(WT.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !searching {
                Text("The factual truths your memories are built on — the people, places, and milestones that must never blur, merge, or drift.")
                    .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.4))
            TextField("Search anchors", text: $searchText)
                .font(.system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    // Flat search across every category's records (title, subtitle, and field values).
    private var searchHits: [(category: AnchorCategory, record: AnchorRecord)] {
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [(AnchorCategory, AnchorRecord)] = []
        for c in AnchorCategory.all {
            for r in store.records(c.id) {
                let hay = (AnchorSchema.title(c.id, r) + " " + AnchorSchema.subtitle(c.id, r) + " " + r.values.values.joined(separator: " ")).lowercased()
                if hay.contains(q) { out.append((c, r)) }
            }
        }
        return out
    }

    private var searchResultsView: some View {
        let hits = searchHits
        return Group {
            if hits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(WT.ink.opacity(0.25))
                    Text("No anchors match “\(searchText)”.")
                        .font(.system(size: 15)).foregroundStyle(WT.ink.opacity(0.5))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                    NavigationLink { AnchorDetailView(category: hit.category, recordID: hit.record.id, store: store) } label: {
                        resultRow(hit.category, hit.record)
                    }
                    .witnessPress()
                }
            }
        }
    }

    private func resultRow(_ c: AnchorCategory, _ r: AnchorRecord) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(c.tone.opacity(0.1)); Image(systemName: c.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(c.tone) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(AnchorSchema.title(c.id, r)).font(.serif(18)).foregroundStyle(WT.ink)
                HStack(spacing: 6) {
                    Text(c.singular).font(.system(size: 12, weight: .medium)).foregroundStyle(c.tone)
                    let sub = AnchorSchema.subtitle(c.id, r)
                    if !sub.isEmpty {
                        Text("·").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.3))
                        Text(sub).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.55))
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard("\(store.totalCount)", "Anchors")
            statCard("\(store.criticalPeople().count)", "Critical people")
        }
    }
    private func statCard(_ n: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(n).font(.serif(26)).foregroundStyle(WV.teal)
            Text(label).font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WT.ink.opacity(0.07), lineWidth: 1))
    }

    private var criticalCard: some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color.white.opacity(0.2)); Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(.white) }
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("Identity Gravity").font(.serif(19)).foregroundStyle(.white)
                Text("The critical people everything else orbits.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x6b5b95), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color(hex: 0x6b5b95).opacity(0.3), radius: 12, y: 6)
    }

    private func categoryCard(_ c: AnchorCategory) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(c.tone.opacity(0.12)); Image(systemName: c.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(c.tone) }
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.label).font(.serif(18)).foregroundStyle(WT.ink)
                Text(c.description).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if store.count(c.id) > 0 {
                Text("\(store.count(c.id))").font(.system(size: 13, weight: .semibold)).foregroundStyle(c.tone)
                    .frame(minWidth: 26, minHeight: 26).background(c.tone.opacity(0.12), in: Circle())
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.05), radius: 9, y: 4)
    }

    private var howItWorks: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(WV.teal).padding(.top, 1)
            Text("When your memories are woven together, anchors hold the facts in place — so names, dates, and places stay true and never merge into one another.")
                .font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).background(WV.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16)).padding(.top, 4)
    }
}

// MARK: - Category list
struct AnchorCategoryView: View {
    let category: AnchorCategory
    @ObservedObject var store: AnchorStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    let items = store.records(category.id)
                    if items.isEmpty { emptyState }
                    else {
                        ForEach(items) { rec in
                            NavigationLink { AnchorDetailView(category: category, recordID: rec.id, store: store) } label: { row(rec) }
                                .witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Anchors").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            NavigationLink { AnchorFormView(category: category, store: store, editingID: nil) } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(category.tone, in: Circle())
            }
            .witnessPress()
            .witnessHint("Add a new \(category.singular.lowercased()) anchor.")
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack { Circle().fill(category.tone.opacity(0.12)); Image(systemName: category.icon).font(.system(size: 20, weight: .medium)).foregroundStyle(category.tone) }
                    .frame(width: 54, height: 54)
                Text(category.label).font(.serif(26)).foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
            }
            Text(category.truthRole).font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ rec: AnchorRecord) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.1)); Image(systemName: category.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(category.tone) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(AnchorSchema.title(category.id, rec)).font(.serif(18)).foregroundStyle(WT.ink)
                let sub = AnchorSchema.subtitle(category.id, rec)
                if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack { Circle().fill(category.tone.opacity(0.1)); Image(systemName: category.icon).font(.system(size: 28)).foregroundStyle(category.tone) }
                .frame(width: 72, height: 72)
            Text("No \(category.singular.lowercased()) anchors yet").font(.serif(20)).foregroundStyle(WT.ink)
            Text("Tap + to add one, or they gather here as you share memories.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }
}

// MARK: - Detail (read-only populated fields) + Edit + Delete
struct AnchorDetailView: View {
    let category: AnchorCategory
    let recordID: String
    @ObservedObject var store: AnchorStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var record: AnchorRecord? { store.record(category.id, id: recordID) }

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            if let rec = record {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(category.tone)
                            Text(AnchorSchema.title(category.id, rec)).font(.serif(28)).foregroundStyle(WT.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(spacing: 0) {
                            let shown = category.fields.filter { !(rec.values[$0.key] ?? "").isEmpty }
                            if shown.isEmpty {
                                Text("No details recorded yet.").font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.45))
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                            }
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, field in
                                if i > 0 { Rectangle().fill(WT.ink.opacity(0.06)).frame(height: 1) }
                                fieldRow(field, value: rec.values[field.key] ?? "")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))

                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("Delete this anchor").font(.system(size: 16, weight: .semibold)).foregroundStyle(WV.danger)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WV.danger.opacity(0.3), lineWidth: 1))
                        }
                        .witnessPress()
                    }
                    .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 40)
                }
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Delete this anchor truth? This removes the record from the factual anchor layer.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(category.id, id: recordID); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: store.totalCount) { _, _ in if record == nil { dismiss() } }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text(category.singular).font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            NavigationLink { AnchorFormView(category: category, store: store, editingID: recordID) } label: {
                Text("Edit").font(.system(size: 16, weight: .medium)).foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private func fieldRow(_ field: FieldConfig, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(field.displayLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(WT.ink.opacity(0.45))
            Text(displayValue(field, value)).font(field.type == .textarea ? .serif(16) : .system(size: 16))
                .foregroundStyle(WT.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
    private func displayValue(_ field: FieldConfig, _ value: String) -> String {
        if field.type == .boolean { return value == "true" ? "Yes" : "No" }
        if field.type == .date, let d = SettingsView.date(fromISO: value) { return SettingsView.displayDate(SettingsView.iso(d)) }
        return value
    }
}

// MARK: - Create / Edit form (data-driven from the category's fields)
struct AnchorFormView: View {
    let category: AnchorCategory
    @ObservedObject var store: AnchorStore
    let editingID: String?
    var preset: [String: String] = [:]

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var activeDateKey: String?
    @State private var pickerDate = Date()

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(editingID == nil ? "New \(category.singular)" : "Edit \(category.singular)")
                        .font(.serif(26)).foregroundStyle(WT.ink)
                    ForEach(category.fields) { field in fieldEditor(field) }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 120)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(get: { activeDateKey != nil }, set: { if !$0 { activeDateKey = nil } })) { dateSheet }
        .onAppear { if values.isEmpty { initValues() } }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: { Text("Cancel").font(.system(size: 16)).foregroundStyle(WT.ink.opacity(0.6)).frame(height: 44) }
                .witnessPress()
            Spacer()
            Button { save() } label: {
                Text("Save").font(.system(size: 16, weight: .semibold)).foregroundStyle(canSave ? WV.teal : WT.ink.opacity(0.3)).frame(height: 44)
            }
            .witnessPress().disabled(!canSave)
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    @ViewBuilder private func fieldEditor(_ field: FieldConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(field.displayLabel).font(.system(size: 13, weight: .medium)).foregroundStyle(WT.ink.opacity(0.6))
                if field.required { Text("*").font(.system(size: 13, weight: .bold)).foregroundStyle(WV.danger) }
            }
            switch field.type {
            case .text:     textField(field, multiline: false)
            case .textarea: textField(field, multiline: true)
            case .select:   selectField(field)
            case .date:     dateField(field)
            case .boolean:  boolField(field)
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func textField(_ field: FieldConfig, multiline: Bool) -> some View {
        TextField(field.displayLabel, text: binding(field.key), axis: multiline ? .vertical : .horizontal)
            .lineLimit(multiline ? 3...8 : 1...1)
            .font(multiline ? .serif(16) : .system(size: 16)).foregroundStyle(WT.ink).tint(WV.teal)
            .textInputAutocapitalization(field.type == .textarea ? .sentences : .words)
            .padding(.horizontal, 14).padding(.vertical, multiline ? 12 : 0).frame(minHeight: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
            .onChange(of: values[field.key] ?? "") { _, v in
                if let m = field.maxLength, v.count > m { values[field.key] = String(v.prefix(m)) }
            }
    }

    private func selectField(_ field: FieldConfig) -> some View {
        Menu {
            Button("— None —") { values[field.key] = "" }
            ForEach(field.options ?? [], id: \.self) { opt in Button(opt) { values[field.key] = opt } }
        } label: {
            HStack {
                Text((values[field.key] ?? "").isEmpty ? "Select" : values[field.key]!)
                    .font(.system(size: 16)).foregroundStyle((values[field.key] ?? "").isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(WT.ink.opacity(0.4))
            }
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
    }

    private func dateField(_ field: FieldConfig) -> some View {
        Button {
            pickerDate = SettingsView.date(fromISO: values[field.key] ?? "") ?? Date()
            activeDateKey = field.key
        } label: {
            HStack {
                Text((values[field.key] ?? "").isEmpty ? "Select date" : SettingsView.displayDate(values[field.key]!))
                    .font(.system(size: 16)).foregroundStyle((values[field.key] ?? "").isEmpty ? WT.ink.opacity(0.4) : WT.ink)
                Spacer()
                Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(WV.teal)
            }
            .padding(.horizontal, 14).frame(height: 50)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func boolField(_ field: FieldConfig) -> some View {
        Toggle(isOn: Binding(get: { (values[field.key] ?? "") == "true" }, set: { values[field.key] = $0 ? "true" : "false" })) {
            Text(field.displayLabel).font(.system(size: 15)).foregroundStyle(WT.ink)
        }
        .tint(WV.teal)
        .padding(.horizontal, 14).frame(minHeight: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(WT.ink.opacity(0.12), lineWidth: 1))
    }

    private var dateSheet: some View {
        VStack(spacing: 16) {
            Capsule().fill(WT.ink.opacity(0.15)).frame(width: 36, height: 5).padding(.top, 10)
            DatePicker("", selection: $pickerDate, displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
            Button {
                if let k = activeDateKey { values[k] = SettingsView.iso(pickerDate) }
                activeDateKey = nil
            } label: {
                Text("Done").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54).background(WV.teal, in: RoundedRectangle(cornerRadius: 16))
            }
            .witnessPress().padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background(WV.parchment).presentationDetents([.height(400)])
    }

    private var canSave: Bool {
        category.fields.filter { $0.required }.allSatisfy { !(values[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func initValues() {
        if let id = editingID, let rec = store.record(category.id, id: id) {
            values = rec.values
        } else {
            var v: [String: String] = [:]
            for field in category.fields { if let d = field.def { v[field.key] = d } }
            for (k, val) in preset { v[k] = val }
            values = v
        }
    }

    private func save() {
        let rec = AnchorRecord(id: editingID ?? UUID().uuidString, values: values)
        store.upsert(category.id, rec)   // POST or PUT /timeline/\(category.id)
        dismiss()
    }
}

// MARK: - Critical People (Identity Gravity) — relationships where significance == Critical
struct CriticalPeopleView: View {
    @ObservedObject var store: AnchorStore
    @Environment(\.dismiss) private var dismiss
    private let category = AnchorCategory.find("relationships")

    var body: some View {
        ZStack(alignment: .top) {
            ParchmentBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IDENTITY GRAVITY").font(.system(size: 12, weight: .semibold)).tracking(1.6).foregroundStyle(Color(hex: 0x6b5b95))
                        Text("Critical People").font(.serif(28)).foregroundStyle(WT.ink)
                        Text("The people who shaped you most — marked Critical, so their truths are protected above all.")
                            .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.6)).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let people = store.criticalPeople()
                    if people.isEmpty { emptyState }
                    else {
                        ForEach(people) { rec in
                            NavigationLink { AnchorDetailView(category: category, recordID: rec.id, store: store) } label: { row(rec) }
                                .witnessPress()
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 110)
            }
            navBar
        }
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)); Text("Anchors").font(.system(size: 16)) }
                    .foregroundStyle(WV.teal).frame(height: 44)
            }.witnessPress()
            Spacer()
            NavigationLink { AnchorFormView(category: category, store: store, editingID: nil, preset: ["significance": "Critical"]) } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Color(hex: 0x6b5b95), in: Circle())
            }
            .witnessPress().witnessHint("Add a critical person — significance is pre-set to Critical.")
        }
        .padding(.horizontal, 16).background(WV.parchment.opacity(0.96))
    }

    private func row(_ rec: AnchorRecord) -> some View {
        HStack(spacing: 14) {
            ZStack { Circle().fill(Color(hex: 0x6b5b95).opacity(0.12)); Image(systemName: "star.fill").font(.system(size: 15)).foregroundStyle(Color(hex: 0x6b5b95)) }
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(AnchorSchema.title("relationships", rec)).font(.serif(18)).foregroundStyle(WT.ink)
                let sub = AnchorSchema.subtitle("relationships", rec)
                if !sub.isEmpty { Text(sub).font(.system(size: 13)).foregroundStyle(WT.ink.opacity(0.55)) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.ink.opacity(0.3))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(WV.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WT.ink.opacity(0.07), lineWidth: 1))
        .shadow(color: WT.ink.opacity(0.04), radius: 8, y: 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack { Circle().fill(Color(hex: 0x6b5b95).opacity(0.1)); Image(systemName: "star").font(.system(size: 28)).foregroundStyle(Color(hex: 0x6b5b95)) }
                .frame(width: 72, height: 72)
            Text("No critical people yet").font(.serif(20)).foregroundStyle(WT.ink)
            Text("Add a person and set their significance to Critical, and they'll appear here.")
                .font(.system(size: 14)).foregroundStyle(WT.ink.opacity(0.55)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }
}
