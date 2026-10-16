import SwiftUI

/// Native anchored menu shared by every planner slot, including the active Meals hub.
struct MealSlotAddMenu<Label: View>: View {
    let onSelect: (MealSlotAddKind) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(MealSlotAddKind.allCases) { kind in
                Button(kind.title, systemImage: kind.systemImage) { onSelect(kind) }
            }
        } label: { label() }
        .menuOrder(.fixed)
    }
}

struct QuickMealEditor: View {
    @ObservedObject var viewModel: MealPlannerViewModel
    let homeID: UUID?
    var entry: QuickPlannedMeal? = nil
    @State var date: Date
    @State var mealType: MealType
    let permissions: HomePermissions
    let onDismiss: () -> Void
    @State private var title = ""
    @State private var requestID = UUID()
    @State private var isSubmitting = false
    @State private var didInitialize = false
    @State private var capturedHomeID: UUID?
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(date.formatted(date: .complete, time: .omitted))
                    Text(mealType.displayName)
                }
                Section("Meal Name") {
                    TextField("Wingstop, Pizza Night, Takeout...", text: $title)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { save() }
                }
                if entry != nil {
                    Section("Reschedule") {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        Picker("Meal Type", selection: $mealType) {
                            ForEach(QuickPlannedMeal.mealTypes) { type in Text(type.displayName).tag(type) }
                        }
                    }
                }
                if didInitialize && homeID != capturedHomeID {
                    Text("The selected Home changed. Close this sheet and reopen Quick Add for the current Home.")
                        .foregroundStyle(.red)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollContentBackground(.hidden)
            .background(HomeyDashboardTheme.appBackground)
            .navigationTitle(entry == nil ? "Quick Add" : "Edit Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss).disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSubmitting { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSubmitting || viewModel.isSaving || homeID == nil || homeID != capturedHomeID || !permissions.meals.canPlanMeals || QuickPlannedMeal.normalizedTitle(title) == nil)
                }
            }
            .disabled(isSubmitting)
        }
        .environment(\.timeZone, viewModel.quickMealCalendar.timeZone)
        .environment(\.calendar, viewModel.quickMealCalendar)
        .tint(HomeyDashboardTheme.warmBrown)
        .interactiveDismissDisabled(isSubmitting)
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            capturedHomeID = homeID
            if let entry { title = entry.title; requestID = entry.id }
            nameFocused = true
        }
    }

    private func save() {
        guard !isSubmitting, let homeID = capturedHomeID, self.homeID == homeID,
              QuickPlannedMeal.normalizedTitle(title) != nil else { return }
        isSubmitting = true
        error = nil
        Task {
            let failure = await viewModel.saveQuickMeal(id: requestID, homeID: homeID, title: title,
                date: date, mealType: mealType, permissions: permissions, existingEntry: entry)
            isSubmitting = false
            if let failure { error = failure } else { onDismiss() }
        }
    }
}

struct QuickMealRows: View {
    @ObservedObject var viewModel: MealPlannerViewModel
    let entries: [QuickPlannedMeal]
    let permissions: HomePermissions
    @State private var editing: QuickPlannedMeal?
    @State private var removing: QuickPlannedMeal?

    var body: some View {
        ForEach(entries) { entry in
            Menu {
                Button("Edit / Reschedule") { editing = entry }.disabled(!permissions.meals.canPlanMeals)
                Button("Remove", role: .destructive) { removing = entry }
                    .disabled(!permissions.meals.canRemovePlannedMeals)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.subheadline.weight(.semibold))
                    Text("\(entry.mealType.displayName) · Quick Add").font(.caption2)
                    Text(entry.plannedDate).font(.caption2)
                }
                .foregroundStyle(HomeyDashboardTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(HomeyDashboardTheme.selectedSidebarBackground, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.isSaving)
        }
        .sheet(item: $editing) { entry in
            QuickMealEditor(viewModel: viewModel, homeID: entry.homeID, entry: entry,
                date: date(for: entry), mealType: entry.mealType, permissions: permissions,
                onDismiss: { editing = nil })
        }
        .confirmationDialog("Remove this Quick Add?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                guard let entry = removing else { return }
                removing = nil
                Task { await viewModel.removeQuickMeal(entry, permissions: permissions) }
            }
        }
    }

    private func date(for entry: QuickPlannedMeal) -> Date {
        let parts = entry.plannedDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return viewModel.quickMealCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }
}
