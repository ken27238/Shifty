//
//  ShiftySchema.swift
//  Shifty
//

import SwiftData

// Every Shifty model. All containers — app, widgets, watch, intents,
// previews, and tests — must agree on this schema; when adding a new
// @Model, this is the only place to update.

nonisolated extension Schema {
    static let shifty = Schema(ShiftyModels.all)
}

/// Model-type list form, for APIs like `.modelContainer(for:)`.
nonisolated enum ShiftyModels {
    static let all: [any PersistentModel.Type] = [
        Shift.self,
        Job.self,
        ShiftPreset.self,
    ]
}
