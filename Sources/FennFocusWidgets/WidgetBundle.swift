import WidgetKit
import SwiftUI

@main
struct FennFocusWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        FennTodayDesktopWidget()
        FennTasksDesktopWidget()
        FennHabitsDesktopWidget()
        FennFocusDesktopWidget()
        FennAgentDesktopWidget()
    }
}
