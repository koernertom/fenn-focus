import FennFocusCore
import SwiftUI
import WidgetKit

// Desktop widgets: today, tasks, routines, Fenn, plus the Pomodoro.
// The views (clay look) live in DesktopClayViews.swift.

struct FennTodayDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FennToday", provider: FennDesktopProvider()) { entry in
            FennTodayDesktopView(entry: entry)
        }
        .configurationDisplayName("Fenn")
        .description("Nächster Termin, Fokuszeit, erledigte Aufgaben und Routinen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FennTasksDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FennTasks", provider: FennDesktopProvider()) { entry in
            FennTasksDesktopView(entry: entry)
        }
        .configurationDisplayName("Ziele & Aufgaben")
        .description("Deine Ziele und die Aufgaben von heute – direkt im Widget abhaken.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FennHabitsDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FennHabits", provider: FennDesktopProvider()) { entry in
            FennHabitsDesktopView(entry: entry)
        }
        .configurationDisplayName("Routinen")
        .description("Deine Routinen von heute – direkt im Widget abhaken.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FennAgentDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FennAgent", provider: PebbleDesktopProvider()) { entry in
            FennAgentDesktopView(entry: entry)
        }
        .configurationDisplayName("Fenn")
        .description("Fenn auf dem Schreibtisch – klicken, und du sprichst mit ihm.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct FennFocusDesktopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FennFocus", provider: FennDesktopProvider()) { entry in
            FennFocusDesktopView(entry: entry)
        }
        .configurationDisplayName("Pomodoro")
        .description("Arbeits- und Pausenblöcke. Länge stellst du in Fenn ein, auch per Sprache.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
