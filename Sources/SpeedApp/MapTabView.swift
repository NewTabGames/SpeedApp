import SwiftUI
import MapKit
import UIKit

struct MapTabView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var navigation: NavigationStore
    @EnvironmentObject var settings: SettingsStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var selectedMapItem: MapSelection<MKMapItem>?
    /// When true, the camera stays pinned to the rider's location as they move ("lock on").
    @State private var followMode = false
    @State private var showHeatmap = false
    /// Best-effort current zoom span, so recentering doesn't also change the zoom level.
    @State private var currentSpan: MKCoordinateSpan?
    @FocusState private var searchFocused: Bool

    private func recenterOnUser(zoom: Bool = false) {
        guard let coord = location.currentLocation?.coordinate else {
            cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            return
        }
        let span = zoom
            ? MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            : (currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(MKCoordinateRegion(center: coord, span: span))
        }
    }

    /// Turns lock-on follow mode on or off. When on, the camera is handed to MapKit's own
    /// user-tracking mode, which keeps it pinned to the rider as they move — no manual
    /// recentering needed. When off, the camera freezes wherever it is so they can pan around.
    private func setFollowMode(_ on: Bool) {
        followMode = on
        if on {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            }
        } else {
            // Turning follow OFF has to actively freeze the camera. `.userLocation` is
            // itself what makes MapKit track the rider — leave it set and the map keeps
            // following, which made the toggle appear to do nothing on release.
            if let coord = location.currentLocation?.coordinate {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: currentSpan ?? MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $cameraPosition, selection: $selectedMapItem) {
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
                    MapCompass()
                }
                // Push MapKit's own controls (like the compass) down so they don't sit
                // underneath the search bar / navigation banner at the top of the screen.
                // The banner during active navigation is taller than the search bar, so
                // this is sized for the taller of the two.
                .safeAreaPadding(.top, navigation.isNavigating ? 120 : 70)
                .onMapCameraChange { context in
                    currentSpan = context.region.span
                }
                // Long-press anywhere on the map to drop a pin there as your destination.
                .gesture(
                    LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard case .second(true, let drag?) = value else { return }
                            if let coordinate = proxy.convert(drag.location, from: .local) {
                                Haptics.impact()
                                navigation.setDestination(
                                    coordinate: coordinate,
                                    currentCoordinate: location.currentLocation?.coordinate
                                )
                            }
                        }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            VStack(spacing: 12) {
                if navigation.isNavigating {
                    navigationBanner
                } else {
                    searchBar
                    if !navigation.suggestions.isEmpty {
                        suggestionsList
                    } else if navigation.route != nil {
                        routePreviewCard
                    } else {
                        Text("Tap a place on the map, or press and hold to drop a pin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal)
            // Without this, SwiftUI slides the whole overlay upward to keep the focused
            // text field above the keyboard — which shoves the search bar off the top of
            // the screen. The bar is already at the top and never obscured, so the
            // avoidance is pure harm here.
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // Floating map controls, bottom-right.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // Heatmap: all your recorded routes overlaid on one map.
                        Button {
                            Haptics.tap()
                            showHeatmap = true
                        } label: {
                            Image(systemName: "flame.fill")
                                .font(.title3)
                                .foregroundStyle(settings.accent.color)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }

                        // Lock-on: hand the camera to MapKit's user-tracking so it follows
                        // me as I move. Toggle.
                        Button {
                            setFollowMode(!followMode)
                            Haptics.tap()
                        } label: {
                            Image(systemName: followMode ? "location.fill.viewfinder" : "location.viewfinder")
                                .font(.title2)
                                .foregroundStyle(followMode ? .white : settings.accent.color)
                                .frame(width: 48, height: 48)
                                .background(followMode ? AnyShapeStyle(settings.accent.color) : AnyShapeStyle(.ultraThinMaterial))
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }

                        // One-shot recenter: snap back to me. Also cancels lock-on, since
                        // this is a "just look here once" action.
                        Button {
                            if followMode { followMode = false }
                            recenterOnUser()
                            Haptics.tap()
                        } label: {
                            Image(systemName: "location")
                                .font(.title2)
                                .foregroundStyle(settings.accent.color)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        // Tapping a point of interest on the map (restaurant, shop, park, etc.) sets it as the destination.
        .onChange(of: selectedMapItem) { _, selection in
            guard let mapItem = selection?.value else { return }
            navigation.setDestination(
                coordinate: mapItem.placemark.coordinate,
                name: mapItem.name,
                currentCoordinate: location.currentLocation?.coordinate
            )
            selectedMapItem = nil
        }
        .onAppear {
            location.requestPermission()
            location.start()
        }
        .sheet(isPresented: $showHeatmap) {
            NavigationStack {
                HeatmapView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") { showHeatmap = false }
                        }
                    }
            }
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
        // Scrollable and height-capped: the completer can return a dozen results, and an
        // unbounded stack would run off the bottom of the screen (and, with the keyboard up,
        // drag the search bar off the top with it).
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(navigation.suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.tap()
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
        }
        .frame(maxHeight: 280)
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
            if navigation.isRerouting {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recalculating route…")
                        .font(.headline)
                    Spacer()
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.title2)
                        .foregroundStyle(settings.accent.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(navigation.currentInstruction)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text("in \(distanceString(navigation.distanceToNextManeuverMeters))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if navigation.isOffRoute {
                                Text("• Off route")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                    Button {
                        navigation.voiceEnabled.toggle()
                    } label: {
                        Image(systemName: navigation.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundStyle(.secondary)
                    }
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
