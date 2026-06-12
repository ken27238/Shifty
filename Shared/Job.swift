//
//  Job.swift
//  Shifty
//

import SwiftUI
import SwiftData
import CoreLocation

// CloudKit sync requires every property to have a default value
// and relationships to be optional.
@Model
final class Job {
    var name: String = ""
    var hourlyRate: Double = 0
    var colorName: String = "blue"
    /// Workplace location, shown on the Home map for upcoming shifts.
    var locationName: String = ""
    var latitude: Double?
    var longitude: Double?
    /// Archived jobs keep their history but leave the pickers.
    var archived: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Shift.job)
    var shifts: [Shift]? = []

    init(name: String, hourlyRate: Double, colorName: String = "blue") {
        self.name = name
        self.hourlyRate = hourlyRate
        self.colorName = colorName
    }

    var color: Color {
        Job.palette[colorName] ?? .accentColor
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// System colors only, so they adapt to light/dark mode automatically.
    static let palette: [String: Color] = [
        "red": .red,
        "orange": .orange,
        "yellow": .yellow,
        "green": .green,
        "teal": .teal,
        "blue": .blue,
        "indigo": .indigo,
        "purple": .purple,
        "pink": .pink,
        "brown": .brown,
    ]

    static let paletteOrder = [
        "red", "orange", "yellow", "green", "teal",
        "blue", "indigo", "purple", "pink", "brown",
    ]
}
