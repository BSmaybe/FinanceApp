import SwiftUI

enum AppTheme {
    private static var p: ThemePalette { ThemeStore.shared.palette }

    static var canvas: Color           { p.canvas }
    static var surface: Color          { p.surface }
    static var elevatedSurface: Color  { p.surface }
    static var outline: Color          { p.outline }

    static var primaryAccent: Color    { p.primaryAccent }
    static var secondaryAccent: Color  { p.secondaryAccent }
    static var danger: Color           { p.danger }
    static var success: Color          { p.success }

    static var heroCardTitle: Color    { p.heroCardTitle }
    static var heroCardLabel: Color    { p.heroCardLabel }

    static var timelineLine: Color     { p.timelineLine }
    static var timelineDot: Color      { p.timelineDot }

    static var heroGradient: LinearGradient         { p.heroGradient }
    static var incomeGradient: LinearGradient       { p.incomeGradient }
    static var expenseGradient: LinearGradient      { p.expenseGradient }
    static var debtGradient: LinearGradient         { p.debtGradient }
    static var subscriptionGradient: LinearGradient { p.subscriptionGradient }
    static var fabGradient: LinearGradient          { p.fabGradient }
}
