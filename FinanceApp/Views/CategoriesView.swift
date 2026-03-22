import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.name)]) private var categories: [Category]
    @Query private var budgets: [Budget]

    @State private var showingAdd = false
    @State private var editingCategory: Category? = nil
    @State private var categoryPendingDelete: Category?
    @State private var showingDeleteConfirmation = false

    private var incomeCategories: [Category] { categories.filter { $0.type == .income } }
    private var expenseCategories: [Category] { categories.filter { $0.type == .expense } }

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Income")) {
                    if incomeCategories.isEmpty {
                        Text(String(localized: "No income categories.")).foregroundStyle(.secondary)
                    } else {
                        ForEach(incomeCategories) { cat in
                            CategoryRow(category: cat)
                                .contextMenu {
                                    Button(String(localized: "Edit")) { editingCategory = cat }
                                }
                        }
                        .onDelete { offsets in
                            requestDeleteCategory(from: incomeCategories, at: offsets)
                        }
                        .onMove { from, to in
                            moveCategories(incomeCategories, from: from, to: to)
                        }
                    }
                }

                Section(String(localized: "Expense")) {
                    if expenseCategories.isEmpty {
                        Text(String(localized: "No expense categories.")).foregroundStyle(.secondary)
                    } else {
                        ForEach(expenseCategories) { cat in
                            CategoryRow(category: cat)
                                .contextMenu {
                                    Button(String(localized: "Edit")) { editingCategory = cat }
                                }
                        }
                        .onDelete { offsets in
                            requestDeleteCategory(from: expenseCategories, at: offsets)
                        }
                        .onMove { from, to in
                            moveCategories(expenseCategories, from: from, to: to)
                        }
                    }
                }
            }
            .overlay {
                if categories.isEmpty {
                    EmptyStateView(
                        icon: "tag.fill",
                        title: String(localized: "No Categories"),
                        subtitle: String(localized: "Create categories to organise your spending")
                    )
                }
            }
            .navigationTitle(String(localized: "Categories"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("categories.screen")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        EditButton()
                        Button { showingAdd = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditCategoryView()
            }
            .sheet(item: $editingCategory) { cat in
                AddEditCategoryView(category: cat)
            }
            .alert("Delete Category", isPresented: $showingDeleteConfirmation, presenting: categoryPendingDelete) { category in
                Button("Delete", role: .destructive) {
                    // Delete matching budgets first
                    for budget in budgets where budget.categoryId == category.id {
                        modelContext.delete(budget)
                    }
                    modelContext.delete(category)
                    do {
                        try modelContext.save()
                    } catch {
                        print("Save error: \(error)")
                    }
                    categoryPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    categoryPendingDelete = nil
                }
            } message: { _ in
                Text("Transactions in this category will become uncategorized.")
            }
        }
    }

    private func moveCategories(_ list: [Category], from source: IndexSet, to destination: Int) {
        var reordered = list
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in reordered.enumerated() {
            cat.sortOrder = index
        }
    }

    private func requestDeleteCategory(from list: [Category], at offsets: IndexSet) {
        if let index = offsets.first {
            categoryPendingDelete = list[index]
            showingDeleteConfirmation = true
        }
    }
}

private struct CategoryRow: View {
    let category: Category

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconName)
                .font(.body)
                .foregroundStyle(Color(hex: category.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: category.colorHex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(category.name)
            Spacer()
            Text(category.type.localizedName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AddEditCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingCategory: Category?

    @State private var name: String
    @State private var type: CategoryType
    @State private var selectedColor: Color
    @State private var selectedIcon: String

    init(category: Category? = nil) {
        self.existingCategory = category
        if let c = category {
            _name = State(initialValue: c.name)
            _type = State(initialValue: c.type)
            _selectedColor = State(initialValue: Color(hex: c.colorHex))
            _selectedIcon = State(initialValue: c.iconName)
        } else {
            _name = State(initialValue: "")
            _type = State(initialValue: .expense)
            _selectedColor = State(initialValue: Color(hex: "#888888"))
            _selectedIcon = State(initialValue: "folder")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Name")) {
                    TextField(String(localized: "Category name"), text: $name)
                }
                Section(String(localized: "Type")) {
                    Picker(String(localized: "Type"), selection: $type) {
                        ForEach(CategoryType.allCases, id: \.self) { t in
                            Text(t.localizedName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(String(localized: "Icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                        ForEach(Category.availableIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 36, height: 36)
                                    .background(selectedIcon == icon ? selectedColor.opacity(0.2) : Color.clear)
                                    .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedIcon == icon ? selectedColor : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(String(localized: "Color")) {
                    ColorPicker(String(localized: "Color"), selection: $selectedColor, supportsOpacity: false)
                }
            }
            .navigationTitle(existingCategory == nil ? String(localized: "New Category") : String(localized: "Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let hexColor = selectedColor.toHex()
        if let existing = existingCategory {
            existing.name = trimmedName
            existing.type = type
            existing.colorHex = hexColor
            existing.iconName = selectedIcon
        } else {
            let cat = Category(name: trimmedName, type: type, colorHex: hexColor, iconName: selectedIcon)
            modelContext.insert(cat)
        }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
        dismiss()
    }
}
