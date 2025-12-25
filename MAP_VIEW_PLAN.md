# Map View V1 Plan — Legal Cannabis Regions

**Status**: Planning Phase (Phase 11 of R1)
**Date**: December 25, 2025
**Goal**: Display world map highlighting where cannabis is legal (countries + US states)
**Timeline**: 4 hours

---

## Overview

**Map View V1**: Simple visualization showing legal cannabis regions

**Key Principle**: **NO memory pins in V1** (deferred to V2)

**Purpose**:
- Educational: Show users where cannabis is legal globally
- Discovery: Highlight travel destinations
- Community: Build awareness of legal landscape
- Engagement: Placeholder for future memory mapping

---

## Design Spec

### Main View

```
┌──────────────────────────────────────────┐
│           Cannabis Legal Map             │
│                                          │
│   ┌────────────────────────────────────┐ │
│   │                                    │ │
│   │   [ INTERACTIVE WORLD MAP ]        │ │
│   │                                    │ │
│   │   🟢 Green = Recreational Legal    │ │
│   │   🟡 Yellow = Medical Only         │ │
│   │   ⚪ Gray = Illegal/Decriminalized │ │
│   │                                    │ │
│   └────────────────────────────────────┘ │
│                                          │
│   Tap a region to learn more            │
│                                          │
└──────────────────────────────────────────┘
```

### Region Detail Sheet (Tap a Region)

```
┌──────────────────────────────────────────┐
│ 🇨🇦 Canada                               │
│                                          │
│ Status: Recreational Legal ✅            │
│ Since: October 2018                      │
│                                          │
│ Personal Possession: 30g                 │
│ Home Cultivation: 4 plants               │
│                                          │
│ [ Learn More ]   [ Close ]               │
└──────────────────────────────────────────┘
```

---

## Legal Regions Data

### Countries (Recreational Legal)

| Country | Flag | Legal Since | Possession Limit | Home Cultivation |
|---------|------|-------------|------------------|------------------|
| 🇨🇦 Canada | 🇨🇦 | Oct 2018 | 30g | 4 plants |
| 🇺🇾 Uruguay | 🇺🇾 | Dec 2013 | 40g/month | 6 plants |
| 🇲🇽 Mexico | 🇲🇽 | Jun 2021 | 28g | 4-6 plants |
| 🇹🇭 Thailand | 🇹🇭 | Jun 2022 | No limit (decriminalized) | Unlimited |
| 🇲🇹 Malta | 🇲🇹 | Dec 2021 | 7g | 4 plants |
| 🇱🇺 Luxembourg | 🇱🇺 | Jul 2023 | 3g | 4 plants |
| 🇩🇪 Germany | 🇩🇪 | Apr 2024 | 25g | 3 plants |
| 🇨🇿 Czech Republic | 🇨🇿 | Decriminalized | 10g | 5 plants |

### US States (Recreational Legal)

| State | Abbreviation | Legal Since | Possession Limit |
|-------|-------------|-------------|------------------|
| Alaska | AK | Feb 2015 | 1 oz |
| Arizona | AZ | Nov 2020 | 1 oz |
| California | CA | Jan 2018 | 1 oz |
| Colorado | CO | Jan 2014 | 1 oz |
| Connecticut | CT | Jul 2021 | 1.5 oz |
| Delaware | DE | Apr 2023 | 1 oz |
| Illinois | IL | Jan 2020 | 1 oz |
| Maine | ME | Jan 2017 | 2.5 oz |
| Maryland | MD | Jul 2023 | 1.5 oz |
| Massachusetts | MA | Dec 2016 | 1 oz |
| Michigan | MI | Dec 2019 | 2.5 oz |
| Minnesota | MN | Aug 2023 | 2 oz |
| Missouri | MO | Feb 2023 | 3 oz |
| Montana | MT | Jan 2021 | 1 oz |
| Nevada | NV | Jul 2017 | 1 oz |
| New Jersey | NJ | Apr 2022 | 1 oz |
| New Mexico | NM | Apr 2022 | 2 oz |
| New York | NY | Mar 2021 | 3 oz |
| Ohio | OH | Dec 2023 | 2.5 oz |
| Oregon | OR | Jul 2015 | 1 oz |
| Rhode Island | RI | Dec 2022 | 1 oz |
| Vermont | VT | Jul 2018 | 1 oz |
| Virginia | VA | Jul 2021 | 1 oz |
| Washington | WA | Dec 2012 | 1 oz |
| Washington DC | DC | Feb 2015 | 2 oz |

---

## Technical Implementation

### MapView.swift (200 lines)

```swift
import SwiftUI
import MapKit

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 180)
    )
    @State private var selectedRegion: LegalRegion?
    @State private var showingDetail = false

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: []) { _ in
                // No annotations in V1
            }
            .overlay(
                // Overlay polygons for legal regions
                LegalRegionsOverlay()
            )
            .ignoresSafeArea()

            // Legend
            VStack {
                HStack {
                    LegendItem(color: .green, label: "Recreational Legal")
                    LegendItem(color: .yellow, label: "Medical Only")
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding()

                Spacer()
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let region = selectedRegion {
                RegionDetailView(region: region)
            }
        }
    }
}
```

---

### LegalRegions.swift (Data Model) (100 lines)

```swift
import Foundation
import MapKit

struct LegalRegion: Identifiable {
    let id: String
    let name: String
    let flag: String
    let status: LegalStatus
    let legalSince: String
    let possessionLimit: String
    let homeCultivation: String
    let coordinates: [CLLocationCoordinate2D]  // Polygon boundary

    enum LegalStatus: String {
        case recreational = "Recreational Legal"
        case medical = "Medical Only"
        case decriminalized = "Decriminalized"
        case illegal = "Illegal"
    }
}

extension LegalRegion {
    static let countries: [LegalRegion] = [
        LegalRegion(
            id: "canada",
            name: "Canada",
            flag: "🇨🇦",
            status: .recreational,
            legalSince: "October 2018",
            possessionLimit: "30g",
            homeCultivation: "4 plants",
            coordinates: [/* Canada polygon */]
        ),
        LegalRegion(
            id: "uruguay",
            name: "Uruguay",
            flag: "🇺🇾",
            status: .recreational,
            legalSince: "December 2013",
            possessionLimit: "40g/month",
            homeCultivation: "6 plants",
            coordinates: [/* Uruguay polygon */]
        ),
        // ... more countries
    ]

    static let usStates: [LegalRegion] = [
        LegalRegion(
            id: "california",
            name: "California",
            flag: "🇺🇸",
            status: .recreational,
            legalSince: "January 2018",
            possessionLimit: "1 oz (28g)",
            homeCultivation: "6 plants",
            coordinates: [/* California polygon */]
        ),
        // ... more states
    ]

    static let all = countries + usStates
}
```

---

### LegalRegionsOverlay.swift (Map Overlay)

```swift
import SwiftUI
import MapKit

struct LegalRegionsOverlay: View {
    var body: some View {
        ForEach(LegalRegion.all) { region in
            MapPolygon(coordinates: region.coordinates)
                .foregroundStyle(
                    region.status == .recreational ? Color.green.opacity(0.3) :
                    region.status == .medical ? Color.yellow.opacity(0.3) :
                    Color.gray.opacity(0.1)
                )
                .stroke(
                    region.status == .recreational ? Color.green :
                    region.status == .medical ? Color.yellow :
                    Color.gray,
                    lineWidth: 2
                )
        }
    }
}
```

---

### RegionDetailView.swift (Detail Sheet)

```swift
struct RegionDetailView: View {
    let region: LegalRegion

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(region.flag)
                    .font(.system(size: 60))
                VStack(alignment: .leading) {
                    Text(region.name)
                        .font(.budsTitle)
                    Text(region.status.rawValue)
                        .font(.budsBody)
                        .foregroundColor(region.status == .recreational ? .green : .yellow)
                }
                Spacer()
            }
            .padding()

            // Details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Legal Since", value: region.legalSince)
                DetailRow(label: "Possession Limit", value: region.possessionLimit)
                DetailRow(label: "Home Cultivation", value: region.homeCultivation)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding()

            Spacer()

            // Learn More Button
            Button(action: {
                // Open Wikipedia or government website
                if let url = URL(string: "https://en.wikipedia.org/wiki/Legality_of_cannabis") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Learn More")
                    .font(.budsButton)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.budsPrimary)
                    .cornerRadius(12)
            }
            .padding()
        }
        .presentationDetents([.medium])
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.budsBody)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.budsBody)
                .fontWeight(.semibold)
        }
    }
}
```

---

## Polygon Coordinates

### Sourcing Polygon Data

**Option 1: Natural Earth Data** (Free, Public Domain)
- Download country/state shapefiles from [Natural Earth](https://www.naturalearthdata.com/)
- Convert to GeoJSON
- Parse in Swift and convert to `CLLocationCoordinate2D`

**Option 2: MapKit Geocoder** (Simpler, Less Accurate)
- Use simplified bounding boxes for countries/states
- Trade accuracy for simplicity

**Recommendation for V1**: Use bounding boxes (Option 2) for speed, upgrade to accurate polygons in V2.

### Bounding Box Example (California)

```swift
extension LegalRegion {
    static let california = LegalRegion(
        id: "california",
        name: "California",
        flag: "🇺🇸",
        status: .recreational,
        legalSince: "January 2018",
        possessionLimit: "1 oz (28g)",
        homeCultivation: "6 plants",
        coordinates: [
            CLLocationCoordinate2D(latitude: 42.0, longitude: -124.4),  // NW
            CLLocationCoordinate2D(latitude: 42.0, longitude: -114.1),  // NE
            CLLocationCoordinate2D(latitude: 32.5, longitude: -114.1),  // SE
            CLLocationCoordinate2D(latitude: 32.5, longitude: -124.4),  // SW
        ]
    )
}
```

---

## User Interaction

### V1 Interactions:
1. **Pan/Zoom**: Standard MapKit gestures
2. **Tap Region**: Show detail sheet with legal info
3. **Legend**: Static legend in top-left corner

### Deferred to V2:
- Search bar (find a country/state)
- Filter by legal status (show only recreational, hide medical)
- Memory pins (tap jar → show buds on map)
- Clustering (group nearby memory pins)

---

## Performance Optimization

### Challenge: Rendering 24+ Polygons (Countries + States)

**Solution 1**: Lazy rendering
- Only render polygons in visible map region
- Hide polygons when zoomed out too far

**Solution 2**: Use MapKit overlays (not SwiftUI shapes)
- More performant for complex polygons
- Native rendering

**Recommendation**: Start with SwiftUI shapes for V1 (24 regions is manageable), optimize in V2 if slow.

---

## Testing Plan

### Test Cases:
1. **Map loads**: World map displays, no crashes
2. **Polygons render**: Green/yellow overlays visible
3. **Tap region**: Detail sheet appears with correct data
4. **Pan/zoom**: Smooth 60 FPS performance
5. **Dark mode**: Overlays visible in dark mode
6. **iPad layout**: Map fills screen properly

### Edge Cases:
- Tap outside polygons → No detail sheet
- Zoom in very close → Polygons still visible
- Rotate device → Map reorients correctly

---

## Accessibility

- VoiceOver: Read region name when tapping polygon
- Dynamic Type: Detail sheet text scales with user font size
- Color blindness: Use patterns (not just color) for legal status

---

## Localization (Deferred to V2)

**V1**: English only

**V2**: Translate region details to:
- Spanish (Mexico, Uruguay, Spain)
- German (Germany, Luxembourg)
- French (Canada, Luxembourg)
- Thai (Thailand)

---

## Implementation Checklist

- [ ] Create `MapView.swift` (main view)
- [ ] Create `LegalRegions.swift` (data model)
- [ ] Create `RegionDetailView.swift` (detail sheet)
- [ ] Add bounding box coordinates for all 24+ regions
- [ ] Test on iPhone 15 Pro (iOS 18)
- [ ] Test on iPad Pro (iOS 18)
- [ ] Test in dark mode
- [ ] Test VoiceOver accessibility
- [ ] Update `MainTabView.swift` (replace placeholder)
- [ ] Add Map icon to tab bar

---

## Files Created/Modified

**Created** (3 files):
- `Buds/Features/Map/MapView.swift` (200 lines)
- `Buds/Features/Map/LegalRegions.swift` (100 lines)
- `Buds/Features/Map/RegionDetailView.swift` (80 lines)

**Modified** (1 file):
- `Buds/Features/MainTabView.swift` (replace "Coming Soon" with MapView)

**Total**: ~380 lines of code

---

## Timeline

| Task | Time |
|------|------|
| Create `LegalRegions.swift` (data model + bounding boxes) | 1h |
| Create `MapView.swift` (main view + overlays) | 1.5h |
| Create `RegionDetailView.swift` (detail sheet) | 1h |
| Testing (iOS 17-18, iPad, dark mode) | 30m |
| **Total** | **4 hours** |

---

## Future Enhancements (V2)

### Memory Pins on Map
- Show all buds as pins
- Color-coded by jar
- Tap pin → Open MemoryDetailView
- Clustering for dense areas

### Search + Filters
- Search for country/state
- Filter by legal status
- Filter by jar (show only "Tahoe Trip" buds)

### Heatmap
- Show density of buds (where do you consume most?)
- Time-based heatmap (weekday vs weekend)

### Accurate Polygons
- Download Natural Earth shapefiles
- Parse GeoJSON in Swift
- Render precise country/state boundaries

---

## Success Criteria

- ✅ Map displays with 24+ legal regions highlighted
- ✅ Tapping region shows legal status, possession limits, cultivation
- ✅ 60 FPS scrolling/zooming
- ✅ < 1s load time
- ✅ Works on iPhone + iPad
- ✅ Dark mode support
- ✅ No memory pins (intentionally deferred to V2)

---

## Conclusion

**Map View V1**: Simple, educational, fast to implement (4 hours)

**Purpose**: Show where cannabis is legal, build awareness, placeholder for future memory mapping

**Deferred to V2**: Memory pins, search, filters, clustering

**Ready to implement**: Yes, after Phase 10 (Jar Feed View)

🗺️ Let's map the world.
