//
//  ShiftyWidgetsBundle.swift
//  ShiftyWidgets
//

import WidgetKit
import SwiftUI

@main
struct ShiftyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShiftyWidget()
        WeekWidget()
        PaydayWidget()
        ScheduleWidget()
        MonthWidget()
    }
}
