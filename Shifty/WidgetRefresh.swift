//
//  WidgetRefresh.swift
//  Shifty
//

import WidgetKit

/// Asks the system to update home screen widgets after shift data changes.
@MainActor
func refreshWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
}
