import SwiftUI
import MapKit

struct MapTabView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var navigation: NavigationStore
    @EnvironmentObject var settings: SettingsStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let destination = navigation.destinationCoordinate {
                    Marker(navigation.destinationName.isEmpty ? "Destination" : navigation.destinationName, coordinate: destination)
                        .tint(.red)
                }

                if let route = navigation.route {
                    MapPolyline(route.polyline)
                        .stroke(settings.accent.color, lineWidth: 5)
                }
            }
            .mapStyle(settings.mapStyle.mapStyle)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                if navigation.isNavigating {
                    navigationBanner
                } else {
                    searchBar
                    if !navigation.suggestions.isEmpty {
                        suggestionsList
                    } else if navigation.route != nil {
                        routePreviewCard
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal)
        }
        .onAppear {
            location.requestPermission()
            location.start()
        }
        .onChange(of: navigation.isNavigating) { _, isNav in
            UIApplication.shared.isIdleTimerDisabled = isNav
        }
        .onReceive(location.$currentLocation) { loc in
            if let loc {
                navigation.updateSearchRegion(around: loc.coordinate)
            }
        }
        .alert("You've Arrived", isPresented: $navigation.arrived) {
            Button("OK") { navigation.cancelDestination() }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search for a destination", text: $navigation.searchQuery)
                .focused($searchFocused)
            if !navigation.searchQuery.isEmpty {
                Button {
                    navigation.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
    }

    // MARK: - Suggestions dropdown

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(navigation.suggestions, id: \.self) { suggestion in
                Button {
                    searchFocused = false
                    navigation.selectSuggestion(suggestion, currentCoordinate: location.currentLocation?.coordinate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                if suggestion != navigation.suggestions.last {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
    }

    // MARK: - Route preview (before starting navigation)

    private var routePreviewCard: some View {
        VStack(spacing: 12) {
            if navigation.isCalculatingRoute {
                ProgressView("Finding route…")
                    .padding(.vertical, 8)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(navigation.destinationName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(distanceString(navigation.distanceRemainingMeters)) • \(etaString(navigation.etaMinutes))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button {
                        navigation.cancelDestination()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        navigation.startNavigation()
                    } label: {
                        Text("Start")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(settings.accent.color)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }

    // MARK: - Active navigation banner

    private var navigationBanner: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.title2)
                    .foregroundStyle(settings.accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(navigation.currentInstruction)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("in \(distanceString(navigation.distanceToNextManeuverMeters))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    navigation.voiceEnabled.toggle()
                } label: {
                    Image(systemName: navigation.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(distanceString(navigation.distanceRemainingMeters)) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    navigation.stopNavigation()
                } label: {
                    Text("End")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }

    // MARK: - Formatting helpers

    private func distanceString(_ meters: Double) -> String {
        let converted = settings.unit.convertDistance(fromMiles: meters / 1609.34)
        if converted < 0.1 {
            let feetOrMeters = settings.unit == .mph ? meters * 3.28084 : meters
            return String(format: "%.0f %@", feetOrMeters, settings.unit == .mph ? "ft" : "m")
        }
        return String(format: "%.1f %@", converted, settings.unit.distanceUnitLabel)
    }

    private func etaString(_ minutes: Double) -> String {
        if minutes < 1 { return "<1 min" }
        return String(format: "%.0f min", minutes)
    }
}
