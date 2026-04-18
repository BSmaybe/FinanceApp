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
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                if categories.isEmpty {
                    EmptyStateView(
                        icon: "tag.fill",
                        title: String(localized: "No Categories"),
                        subtitle: String(localized: "Create categories to organise accounts, budgets, and analytics.")
                    )
                } else {
                    List {
                        heroSection
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        categorySection(
                            title: String(localized: "Expense"),
                            subtitle: String(localized: "Flexible, essential, and fixed spending structure."),
                            categories: expenseCategories
                        )

                        categorySection(
                            title: String(localized: "Income"),
                            subtitle: String(localized: "Salary and inflow categories used in planning."),
                            categories: incomeCategories
                        )
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .financeNavigationSurface()
            .navigationTitle(String(localized: "Categories"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("categories.screen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
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
            .sheet(item: $editingCategory) { category in
                AddEditCategoryView(category: category)
            }
            .alert(String(localized: "Delete Category"), isPresented: $showingDeleteConfirmation, presenting: categoryPendingDelete) { category in
                Button(String(localized: "Delete"), role: .destructive) {
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
                Button(String(localized: "Cancel"), role: .cancel) {
                    categoryPendingDelete = nil
                }
            } message: { _ in
                Text(String(localized: "Transactions in this category will become uncategorized."))
            }
        }
    }

    private var heroSection: some View {
        HeroMetricCard(
            title: String(localized: "Financial Structure"),
            value: "\(categories.count)",
            supportingTitle: String(localized: "Expense Categories"),
            supportingValue: "\(expenseCategories.count)",
            note: String(localized: "Category roles shape budgets, analytics, and coach advice."),
            badgeText: String(localized: "Manage")
        )
    }

    private func categorySection(
        title: String,
        subtitle: String,
        categories: [Category]
    ) -> some View {
        Section {
            if categories.isEmpty {
                Text(title == String(localized: "Income")
                     ? String(localized: "No income categories.")
                     : String(localized: "No expense categories."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(categories) { category in
                    CategoryCard(
                        category: category,
                        onEdit: { editingCategory = category },
                        onDelete: {
                            categoryPendingDelete = category
                            showingDeleteConfirmation = true
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button(String(localized: "Edit")) { editingCategory = category }
                        Button(String(localized: "Delete"), role: .destructive) {
                            categoryPendingDelete = category
                            showingDeleteConfirmation = true
                        }
                    }
                }
                .onDelete { offsets in
                    requestDeleteCategory(from: categories, at: offsets)
                }
                .onMove { from, to in
                    moveCategories(categories, from: from, to: to)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)
        }
    }

    private func moveCategories(_ list: [Category], from source: IndexSet, to destination: Int) {
        var reordered = list
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortOrder = index
        }
    }

    private func requestDeleteCategory(from list: [Category], at offsets: IndexSet) {
        if let index = offsets.first {
            categoryPendingDelete = list[index]
            showingDeleteConfirmation = true
        }
    }
}

private struct CategoryCard: View {
    let category: Category
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.iconName)
                .font(.headline)
                .foregroundStyle(Color(hex: category.colorHex))
                .frame(width: 42, height: 42)
                .background(Color(hex: category.colorHex).opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(category.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    InlineStatusPill(
                        title: category.type.localizedName,
                        tint: category.type == .income ? AppTheme.success : AppTheme.info
                    )
                }
                Text(category.adviceRole.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Menu {
                Button(String(localized: "Edit"), action: onEdit)
                Button(String(localized: "Delete"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .cockpitSurface(cornerRadius: 20, elevated: true)
    }
}

private struct InlineStatusPill: View {
    let title: String
    var tint: Color = AppTheme.primaryAccent

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
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
    @State private var selectedAdviceRole: CategoryAdviceRole

    init(category: Category? = nil) {
        self.existingCategory = category
        if let category {
            _name = State(initialValue: category.name)
            _type = State(initialValue: category.type)
            _selectedColor = State(initialValue: Color(hex: category.colorHex))
            _selectedIcon = State(initialValue: category.iconName)
            _selectedAdviceRole = State(initialValue: category.adviceRole)
        } else {
            _name = State(initialValue: "")
            _type = State(initialValue: .expense)
            _selectedColor = State(initialValue: Color(hex: "#888888"))
            _selectedIcon = State(initialValue: "folder")
            _selectedAdviceRole = State(initialValue: .flexible)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        HeroMetricCard(
                            title: existingCategory == nil ? String(localized: "New Category") : String(localized: "Edit Category"),
                            value: name.isEmpty ? String(localized: "Untitled") : name,
                            supportingTitle: String(localized: "Type"),
                            supportingValue: type.localizedName,
                            note: String(localized: "Advice role and icon shape how this category appears across the app."),
                            badgeText: selectedAdviceRole.localizedName
                        )

                        SectionShell(
                            title: String(localized: "Core setup"),
                            subtitle: String(localized: "Name the category and choose the right role before using it in budgets.")
                        ) {
                            VStack(spacing: 14) {
                                textField(title: String(localized: "Name"), text: $name, prompt: String(localized: "Category name"))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Type"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Picker(String(localized: "Type"), selection: $type) {
                                        ForEach(CategoryType.allCases, id: \.self) { categoryType in
                                            Text(categoryType.localizedName).tag(categoryType)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(localized: "Advice Role"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Menu {
                                        ForEach(CategoryAdviceRole.allCases, id: \.self) { role in
                                            Button(role.localizedName) {
                                                selectedAdviceRole = role
                                            }
                                        }
                                    } label: {
                                        selectionLabel(
                                            title: String(localized: "Coach treatment"),
                                            value: selectedAdviceRole.localizedName,
                                            systemImage: "sparkles",
                                            tint: AppTheme.primaryAccent
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    Text(String(localized: "How the coach should treat this category"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        SectionShell(
                            title: String(localized: "Appearance"),
                            subtitle: String(localized: "Use clear icons and colors so transactions scan quickly.")
                        ) {
                            VStack(spacing: 14) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                    ForEach(Category.availableIcons, id: \.self) { icon in
                                        Button {
                                            selectedIcon = icon
                                        } label: {
                                            Image(systemName: icon)
                                                .font(.headline)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 42)
                                                .background(
                                                    selectedIcon == icon
                                                    ? selectedColor.opacity(0.18)
                                                    : AppTheme.elevatedSurface
                                                )
                                                .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .stroke(selectedIcon == icon ? selectedColor : AppTheme.outline.opacity(0.25), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                ColorPicker(String(localized: "Color"), selection: $selectedColor, supportsOpacity: false)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(AppTheme.elevatedSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .financeNavigationSurface()
            .navigationTitle(existingCategory == nil ? String(localized: "New Category") : String(localized: "Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: type) { _, newType in
                if newType == .income {
                    selectedAdviceRole = .income
                } else if selectedAdviceRole == .income {
                    selectedAdviceRole = Category.inferredAdviceRole(name: name, type: newType)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func textField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func selectionLabel(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let hexColor = selectedColor.toHex()
        if let existing = existingCategory {
            existing.name = trimmedName
            existing.type = type
            existing.colorHex = hexColor
            existing.iconName = selectedIcon
            existing.adviceRole = type == .income ? .income : selectedAdviceRole
        } else {
            let category = Category(
                name: trimmedName,
                type: type,
                colorHex: hexColor,
                iconName: selectedIcon,
                adviceRole: type == .income ? .income : selectedAdviceRole
            )
            modelContext.insert(category)
        }
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error)")
        }
        dismiss()
    }
}
