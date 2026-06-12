//
//  WatchWidgetsBundle.swift
//  ShiftyWatchWidgets
//

import WidgetKit
import SwiftUI

@main
struct WatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpNextComplication()
        WeekComplication()
    }
}
