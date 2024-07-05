import SwiftUI
import MapKit
import CoreLocation

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Shift.date, ascending: true)],
        predicate: NSPredicate(format: "date > %@", Calendar.current.startOfDay(for: Date()) as NSDate),
        animation: .default)
    private var upcomingShifts: FetchedResults<Shift>
    
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.appColor) private var colors
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.33233141, longitude: -122.03121860),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )
    @State private var shiftLocations: [Shift: CLLocationCoordinate2D] = [:]
    @State private var mapNeedsUpdate = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    quickGlanceSummaryCard
                    upcomingShiftsSection
                    mapSection
                    weeklyEarningsSection
                    recentActivitySection
                }
                .padding()
            }
            .navigationTitle("Home")
            .background(colors.background.edgesIgnoringSafeArea(.all))
            .onAppear {
                geocodeAddresses()
            }
        }
    }

    private var quickGlanceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's Summary")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            if let todayShift = upcomingShifts.first(where: { Calendar.current.isDateInToday($0.date ?? Date()) }) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(todayShift.name ?? "Unnamed Shift")
                            .font(.subheadline)
                        Text("\(todayShift.startTime ?? Date(), style: .time) - \(todayShift.endTime ?? Date(), style: .time)")
                            .font(.caption)
                    }
                    Spacer()
                    Text(formatCurrency(calculateEarnings(for: todayShift)))
                        .font(.headline)
                }
            } else {
                Text("No shifts scheduled for today")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }

    private var upcomingShiftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Shifts")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            ForEach(Array(Set(upcomingShifts.filter {
                guard let shiftDate = $0.date else { return false }
                return Calendar.current.compare(shiftDate, to: Date(), toGranularity: .day) == .orderedDescending
            })).prefix(3).sorted(by: { ($0.date ?? Date()) < ($1.date ?? Date()) }), id: \.self) { shift in
                HStack {
                    VStack(alignment: .leading) {
                        Text(shift.name ?? "Unnamed Shift")
                            .font(.subheadline)
                            .foregroundColor(colors.text)
                        Text(shift.date ?? Date(), style: .date)
                            .font(.caption)
                            .foregroundColor(colors.secondaryText)
                    }
                    Spacer()
                    Text(shift.startTime ?? Date(), style: .time)
                        .font(.caption)
                        .foregroundColor(colors.secondaryText)
                }
                .padding()
                .background(colors.secondaryBackground)
                .cornerRadius(10)
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shift Locations")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            Map(coordinateRegion: $region, annotationItems: Array(shiftLocations.keys)) { shift in
                MapAnnotation(coordinate: shiftLocations[shift] ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)) {
                    VStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(settingsManager.accentColor)
                            .imageScale(.large)
                        Text(shift.name ?? "")
                            .font(.caption)
                            .fixedSize()
                    }
                }
            }
            .frame(height: 200)
            .cornerRadius(10)
            .onChange(of: mapNeedsUpdate) { _ in
                updateRegion()
            }
        }
    }

    private var weeklyEarningsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Week's Earnings")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            HStack {
                VStack(alignment: .leading) {
                    Text(formatCurrency(calculateWeeklyEarnings()))
                        .font(.title)
                    Text("\(calculateWeeklyHours(), specifier: "%.1f") hours")
                        .font(.subheadline)
                }
                Spacer()
                Circle()
                    .fill(settingsManager.accentColor)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text("\(calculateCompletedShifts())/\(calculateTotalShifts())")
                            .font(.caption)
                            .foregroundColor(.white)
                    )
            }
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(settingsManager.accentColor)
            
            ForEach(upcomingShifts.prefix(3)) { shift in
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(settingsManager.accentColor)
                    Text("\(shift.name ?? "Unnamed Shift") added")
                        .font(.subheadline)
                    Spacer()
                    Text(shift.date ?? Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(colors.secondaryText)
                }
            }
        }
        .padding()
        .background(colors.secondaryBackground)
        .cornerRadius(10)
    }

    private func geocodeAddresses() {
        let geocoder = CLGeocoder()
        for shift in upcomingShifts {
            guard let address = shift.address, !address.isEmpty else { continue }
            geocoder.geocodeAddressString(address) { placemarks, error in
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    return
                }
                if let location = placemarks?.first?.location?.coordinate {
                    DispatchQueue.main.async {
                        self.shiftLocations[shift] = location
                        self.mapNeedsUpdate = true
                    }
                }
            }
        }
    }

    private func updateRegion() {
        guard !shiftLocations.isEmpty else { return }
        let coordinates = shiftLocations.values
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )
        
        region = MKCoordinateRegion(center: center, span: span)
        mapNeedsUpdate = false
    }

    private func calculateEarnings(for shift: Shift) -> Double {
        guard let start = shift.startTime, let end = shift.endTime else { return 0 }
        let duration = end.timeIntervalSince(start) / 3600 // in hours
        return duration * settingsManager.payRate
    }

    private func calculateWeeklyEarnings() -> Double {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekShifts = upcomingShifts.filter { shift in
            guard let shiftDate = shift.date else { return false }
            return calendar.isDate(shiftDate, inSameDayAs: weekStart) || shiftDate > weekStart
        }
        return weekShifts.reduce(0) { $0 + calculateEarnings(for: $1) }
    }

    private func calculateWeeklyHours() -> Double {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekShifts = upcomingShifts.filter { shift in
            guard let shiftDate = shift.date else { return false }
            return calendar.isDate(shiftDate, inSameDayAs: weekStart) || shiftDate > weekStart
        }
        return weekShifts.reduce(0) { total, shift in
            guard let start = shift.startTime, let end = shift.endTime else { return total }
            return total + end.timeIntervalSince(start) / 3600
        }
    }

    private func calculateCompletedShifts() -> Int {
        upcomingShifts.filter { $0.endTime ?? Date() < Date() }.count
    }

    private func calculateTotalShifts() -> Int {
        upcomingShifts.count
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = settingsManager.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .light)
        
        HomeView()
            .environmentObject(SettingsManager())
            .withAppColorScheme()
            .environment(\.colorScheme, .dark)
    }
}
