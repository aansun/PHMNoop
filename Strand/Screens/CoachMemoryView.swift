// === PHM OVERLAY (PHMNOOP) ===
// Coach "Memory" UI: a My-Memory list (filter by category, add) + a detail screen (toggle Active,
// edit, delete). Presented as a sheet from Coach settings. Data lives in CoachMemoryStore; active
// memories feed the Coach system prompt. On-device only — the user fully manages and can delete each.

import SwiftUI
import StrandDesign

// MARK: - Root (sheet)

struct CoachMemoryView: View {
    @StateObject private var store = CoachMemoryStore()
    @Environment(\.dismiss) private var dismiss
    @State private var filter: CoachMemoryCategory? = nil   // nil = All
    @State private var showAdd = false

    private var filtered: [CoachMemory] {
        guard let filter else { return store.memories }
        return store.memories.filter { $0.category == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What the Coach remembers about you. Active memories steer every reply. Everything here is on-device — delete any anytime.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    filterChips

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { memory in
                            NavigationLink(value: memory.id) {
                                CoachMemoryCard(memory: memory)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("My Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: UUID.self) { id in
                CoachMemoryDetailView(memoryID: id, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityLabel("Add memory")
                }
            }
            .sheet(isPresented: $showAdd) {
                CoachMemoryEditor(title: "New memory") { title, detail, category in
                    store.add(title: title, detail: detail, category: category)
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: filter == nil) { filter = nil }
                ForEach(CoachMemoryCategory.allCases) { c in
                    chip(c.displayName, selected: filter == c) { filter = c }
                }
            }
        }
    }

    private func chip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(StrandFont.footnote)
                .foregroundStyle(selected ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(selected ? StrandPalette.accent : StrandPalette.surfaceInset,
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        NoopCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "lightbulb").foregroundStyle(StrandPalette.accent)
                Text("No memories yet")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Tap + to save a goal, an event, or a coaching preference. The Coach will remember it.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Card

private struct CoachMemoryCard: View {
    let memory: CoachMemory

    var body: some View {
        NoopCard(padding: 16, tint: memory.isActive ? StrandPalette.chargeColor : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(memory.title)
                        .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                if !memory.detail.isEmpty {
                    Text(memory.detail)
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    StatusPill(active: memory.isActive)
                    CategoryTag(memory.category)
                }
                HStack(spacing: 6) {
                    Text("Start date: \(memory.createdAt, format: .dateTime.month(.abbreviated).day().year())")
                    if memory.fromConversation {
                        Text("·").opacity(0.6)
                        Label("from chat", systemImage: "text.bubble")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

private struct StatusPill: View {
    let active: Bool
    var body: some View {
        Text(active ? "Active" : "Inactive")
            .font(StrandFont.footnote)
            .foregroundStyle(active ? StrandPalette.accent : StrandPalette.textTertiary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background((active ? StrandPalette.accent : StrandPalette.textTertiary).opacity(0.15),
                        in: Capsule())
    }
}

private struct CategoryTag: View {
    let category: CoachMemoryCategory
    init(_ c: CoachMemoryCategory) { category = c }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.caption2)
            Text(category.displayName).font(StrandFont.footnote)
        }
        .foregroundStyle(StrandPalette.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .overlay(Capsule().strokeBorder(StrandPalette.hairline, lineWidth: 1))
    }
}

// MARK: - Detail

struct CoachMemoryDetailView: View {
    let memoryID: UUID
    @ObservedObject var store: CoachMemoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var memory: CoachMemory? { store.current(memoryID) }

    var body: some View {
        ScrollView {
            if let memory {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(memory.title)
                            .font(StrandFont.title1).foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !memory.detail.isEmpty {
                            Text(memory.detail)
                                .font(StrandFont.body).foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        CategoryTag(memory.category)
                    }

                    activeCard(memory)

                    NoopButton("Edit", systemImage: "pencil", kind: .secondary) { showEdit = true }

                    Text("Saved \(memory.createdAt, format: .dateTime.month(.abbreviated).day().year())")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(16)
            } else {
                // Deleted while open.
                Text("This memory was deleted.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    .padding(24)
            }
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .navigationTitle("Memory")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(StrandPalette.statusCritical)
                .accessibilityLabel("Delete memory")
                .disabled(memory == nil)
            }
        }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let memory { store.delete(memory); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Coach will forget it. This can't be undone.")
        }
        .sheet(isPresented: $showEdit) {
            if let memory {
                CoachMemoryEditor(title: "Edit memory", seed: memory) { t, d, c in
                    var updated = memory
                    updated.title = t; updated.detail = d; updated.category = c
                    store.update(updated)
                }
            }
        }
    }

    private func activeCard(_ memory: CoachMemory) -> some View {
        NoopCard(padding: 16, tint: memory.isActive ? StrandPalette.chargeColor : nil) {
            HStack(spacing: 12) {
                Image(systemName: memory.isActive ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(memory.isActive ? StrandPalette.accent : StrandPalette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    Text(memory.isActive
                         ? "This is actively influencing your coaching."
                         : "Turned off — the Coach ignores this for now.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { memory.isActive },
                    set: { store.setActive(memory, $0) }
                ))
                .labelsHidden()
                .tint(StrandPalette.accent)
                .accessibilityLabel("Active")
            }
        }
    }
}

// MARK: - Add / Edit editor

private struct CoachMemoryEditor: View {
    let title: String
    var seed: CoachMemory? = nil
    let onSave: (String, String, CoachMemoryCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var titleText: String = ""
    @State private var detailText: String = ""
    @State private var category: CoachMemoryCategory = .goal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Title") {
                        TextField("e.g. Minimum pace target", text: $titleText)
                            .textFieldStyle(.plain)
                    }
                    field("Detail") {
                        TextField("e.g. Aiming for a minimum pace of 7.", text: $detailText, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category").strandOverline()
                        Picker("Category", selection: $category) {
                            ForEach(CoachMemoryCategory.allCases) { c in
                                Text(c.displayName).tag(c)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(StrandPalette.accent)
                    }
                }
                .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(titleText, detailText, category)
                        dismiss()
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let seed {
                    titleText = seed.title; detailText = seed.detail; category = seed.category
                }
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).strandOverline()
            content()
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(StrandPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(StrandPalette.hairline, lineWidth: 1))
        }
    }
}
