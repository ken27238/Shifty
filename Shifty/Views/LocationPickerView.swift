//
//  LocationPickerView.swift
//  Shifty
//

import SwiftUI
import MapKit
import CoreLocation

/// Searches Apple Maps for a place and hands back its name and coordinates.
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty {
                    ContentUnavailableView {
                        Label(
                            hasSearched ? "No Places Found" : "Find Your Workplace",
                            systemImage: hasSearched ? "mappin.slash" : "mappin.and.ellipse"
                        )
                    } description: {
                        Text(hasSearched
                             ? "Try a different name or address."
                             : "Search for a business name or address.")
                    }
                } else {
                    List(results, id: \.self) { item in
                        Button {
                            onSelect(item.name ?? query, item.location.coordinate)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? String(localized: "Unknown Place"))
                                    .font(.body)
                                if let address = item.address?.fullAddress {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Job Location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: "Business name or address")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try? await MKLocalSearch(request: request).start()
        results = response?.mapItems ?? []
        hasSearched = true
    }
}
