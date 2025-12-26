# Buds Design System v0.1

Complete design system for Buds iOS app. Updated Dec 2024.

---

## Color Palette

### Core Colors (Xcode Assets)

| Asset Name | Light Mode | Dark Mode | Role |
|------------|------------|-----------|------|
| `budsPrimary` | #1B4332 | #2D6A4F | Primary brand, CTAs |
| `budsPurple` | #3D2645 | #5A3F6B | Secondary brand, accents |
| `budsCream` | #FAF7F2 | #1A1A1A | Root backgrounds |
| `budsSurface` | #FFFFFF | #252525 | Cards, elevated surfaces |
| `budsTextPrimary` | #0F0F0F | #F5F5F5 | Primary text |
| `budsTextSecondary` | #4A4A4A | #B0B0B0 | Secondary text |
| `budsForest` | #52B788 | #40916C | Light green accents |
| `budsLavender` | #8B7D9B | #9D8FB0 | Soft purple accents |
| `budsAmber` | #D4A574 | #C89860 | Warm sun highlights |
| `budsDestructive` | #C1495B | #D95F6F | Delete, errors |
| `budsSuccess` | #52B788 | #40916C | Success states |
| `budsDivider` | #E5E5E5 | #3A3A3A | Borders, separators |

### Legacy Colors (Deprecated - Remove)

These are old and should be replaced:

- `budsAccent` → Use `budsPrimary`
- `budsSecondary` → Use `budsForest`
- `budsWarning` → Use `budsAmber`
- `budsError` → Use `budsDestructive`
- `budsInfo` → Use `budsForest`
- Effect colors → Use new system

---

## Usage Guide

### Backgrounds
```swift
.background(Color.budsCream)          // Root background
.background(Color.budsSurface)        // Cards, sheets
.background(Color.budsPrimary)        // Primary buttons
.background(Color.budsPurple)         // Tags, badges
```

### Text
```swift
.foregroundColor(.budsTextPrimary)    // Headlines, body
.foregroundColor(.budsTextSecondary)  // Captions, metadata
```

### Actions
```swift
Color.budsPrimary      // Primary CTAs
Color.budsForest       // Secondary actions
Color.budsPurple       // Tertiary accents
Color.budsDestructive  // Delete
Color.budsSuccess      // Confirm
Color.budsAmber        // Highlights (stars, special)
```

### Structure
```swift
Color.budsDivider      // Separators, borders
```

---

## Typography

### Font Styles (SwiftUI Extensions)

```swift
// Current system (to update):
.font(.budsTitle)        // 28pt Bold
.font(.budsHeadline)     // 20pt Semibold
.font(.budsBody)         // 16pt Regular
.font(.budsBodyBold)     // 16pt Semibold
.font(.budsCaption)      // 12pt Regular
.font(.budsTag)          // 14pt Medium

// Proposed new system:
.font(.budsTitleLarge)   // 34pt Bold - Page titles
.font(.budsTitle)        // 28pt Bold - Section headers
.font(.budsHeadline)     // 20pt Semibold - Card titles
.font(.budsBody)         // 17pt Regular - Body text
.font(.budsBodyEmphasis) // 17pt Semibold - Emphasized body
.font(.budsCallout)      // 16pt Regular - Secondary info
.font(.budsSubheadline)  // 15pt Regular - Tertiary info
.font(.budsFootnote)     // 13pt Regular - Timestamps
.font(.budsCaption)      // 12pt Regular - Metadata
```

### Text Hierarchy

| Level | Font | Color | Use Case |
|-------|------|-------|----------|
| Page Title | .budsTitleLarge | .budsTextPrimary | Screen titles |
| Section Header | .budsTitle | .budsTextPrimary | "Your Memories" |
| Card Title | .budsHeadline | .budsTextPrimary | Strain name |
| Body | .budsBody | .budsTextPrimary | Notes, descriptions |
| Metadata | .budsCallout | .budsTextSecondary | Rating, method |
| Timestamp | .budsFootnote | .budsTextSecondary | "2 hours ago" |
| Caption | .budsCaption | .budsTextSecondary | Helper text |

---

## Spacing

Current system (to keep):

```swift
enum BudsSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}
```

### Padding Guidelines

- **Cards:** `.padding(.m)` (16pt all sides)
- **Sections:** `.padding(.horizontal, .m)` + `.padding(.vertical, .l)`
- **Buttons:** `.padding(.horizontal, .l)` + `.padding(.vertical, .m)`
- **Stack spacing:** `.spacing(.m)` for VStack/HStack
- **Between cards:** `.spacing(.m)` or `.spacing(.l)`

---

## Corner Radius

```swift
enum BudsRadius {
    static let small: CGFloat = 8      // Tags, badges
    static let medium: CGFloat = 12    // Cards, buttons
    static let large: CGFloat = 16     // Sheets, modals
    static let pill: CGFloat = 100     // Pills, infinite radius
}
```

---

## Shadows

```swift
// Light elevation (cards)
.shadow(color: .black.opacity(0.05), radius: 8, y: 2)

// Medium elevation (floating buttons)
.shadow(color: .black.opacity(0.1), radius: 12, y: 4)

// Heavy elevation (modals)
.shadow(color: .black.opacity(0.15), radius: 20, y: 8)
```

**Dark mode:** Reduce opacity by 50% or remove entirely.

---

## Component Patterns

### Primary Button
```swift
Button("Save") {
    // action
}
.font(.budsBodyBold)
.foregroundColor(.white)
.frame(maxWidth: .infinity)
.padding(.vertical, .m)
.background(Color.budsPrimary)
.cornerRadius(BudsRadius.medium)
```

### Secondary Button
```swift
Button("Cancel") {
    // action
}
.font(.budsBody)
.foregroundColor(.budsTextPrimary)
.frame(maxWidth: .infinity)
.padding(.vertical, .m)
.background(Color.budsSurface)
.overlay(
    RoundedRectangle(cornerRadius: BudsRadius.medium)
        .stroke(Color.budsDivider, lineWidth: 1)
)
.cornerRadius(BudsRadius.medium)
```

### Tag/Chip
```swift
Text("Relaxed")
    .font(.budsCallout)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.budsPurple.opacity(0.15))
    .foregroundColor(.budsPurple)
    .cornerRadius(BudsRadius.pill)
```

### Card
```swift
VStack(alignment: .leading, spacing: .m) {
    // content
}
.padding(.m)
.background(Color.budsSurface)
.cornerRadius(BudsRadius.medium)
.shadow(color: .black.opacity(0.05), radius: 8, y: 2)
```

---

## Effect Tag Colors

Map existing effects to new palette:

| Effect | Color | Opacity |
|--------|-------|---------|
| Relaxed | `budsPurple` | 15% |
| Creative | `budsLavender` | 20% |
| Energized | `budsAmber` | 15% |
| Happy | `budsForest` | 15% |
| Focused | `budsPrimary` | 15% |
| Sleepy | `budsPurple` | 20% |
| Anxious | `budsDestructive` | 15% |
| Euphoric | `budsAmber` | 20% |

Text color: Same as background color but full opacity.

---

## Icon System

### SF Symbols (Primary)

Use SF Symbols 5+ where possible:

- **Add:** `plus.circle.fill`
- **Photo:** `photo.on.rectangle`
- **Camera:** `camera.fill`
- **Star (rating):** `star.fill` / `star`
- **Location:** `location.fill`
- **Delete:** `trash.fill`
- **Edit:** `pencil`
- **Share:** `square.and.arrow.up`
- **Filter:** `line.3.horizontal.decrease.circle`
- **Calendar:** `calendar`
- **Time:** `clock.fill`

### Custom Icons (If Needed)

For cannabis-specific:
- Keep minimal line style
- 2pt stroke weight
- Monochrome (use color via `.foregroundColor()`)
- 24x24pt canvas

**Examples needed:**
- Joint/blunt silhouette
- Bong silhouette  
- Edible (brownie/gummy)
- Vape pen
- Concentrate (dab rig)

**Do NOT use:** Emoji, neon outlines, stoner clichés.

---

## Animation

### Standard Easing
```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
```

### Smooth Fade
```swift
.transition(.opacity)
.animation(.easeInOut(duration: 0.2), value: isVisible)
```

### Button Press
```swift
.scaleEffect(isPressed ? 0.95 : 1.0)
.animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
```

---

## Dark Mode Strategy

### Automatic Adaptation

All colors have dark variants in Xcode Assets. Use semantic colors:

```swift
// ✅ Good (adapts automatically)
.background(Color.budsCream)
.foregroundColor(.budsTextPrimary)

// ❌ Bad (hardcoded)
.background(Color(hex: "#FAF7F2"))
```

### Dark Mode Testing
Test every screen in both modes:
1. Simulator → Settings → Developer → Appearance
2. Or: Xcode Preview with `.preferredColorScheme(.dark)`

---

## Accessibility

### Contrast Requirements

All text/background pairings meet minimum contrast:

- `budsTextPrimary` on `budsCream`: ✅ High contrast
- `budsTextSecondary` on `budsCream`: ✅ Readable
- White text on `budsPrimary`: ✅ High contrast
- White text on `budsPurple`: ✅ High contrast

### Dynamic Type Support

Use `.font(.budsBody)` instead of fixed sizes. SwiftUI scales automatically.

For custom layouts:
```swift
@ScaledMetric var spacing: CGFloat = 16
```

### VoiceOver Labels
```swift
Button("Delete") { }
    .accessibilityLabel("Delete memory")
    .accessibilityHint("Removes this memory from your timeline")
```

---

## Brand Personality

### Voice
- **Chill, not clinical:** "Your memories" not "User data"
- **Friendly, not juvenile:** Avoid "dope" "lit" "fire"
- **Inclusive:** Never assume experience level

### Tone Examples

| Context | ❌ Bad | ✅ Good |
|---------|-------|---------|
| Empty state | "No data found" | "No memories yet" |
| Error | "Operation failed" | "Couldn't save that" |
| Success | "Record created" | "Memory saved" |
| Delete confirm | "Are you sure?" | "Delete this memory?" |

### Microcopy Guidelines
- Use sentence case, not Title Case
- No periods on single-sentence labels
- Keep CTAs active: "Save memory" not "Memory saved"

---

## File Structure

```swift
Shared/
├── Utilities/
│   ├── Colors.swift       // Update with new system
│   ├── Typography.swift   // Update with new fonts
│   ├── Spacing.swift      // Already good
│   └── Radius.swift       // Add this
├── Views/
│   ├── BudsButton.swift        // Reusable button component
│   ├── BudsCard.swift          // Card wrapper
│   ├── BudsTag.swift           // Tag/chip component
│   └── BudsTextField.swift     // Styled text field
```

---

## Next Steps (Migration)

1. **Update Colors.swift** with new palette
2. **Update Typography.swift** with new scale
3. **Create Radius.swift** enum
4. **Replace all old color references** (find/replace)
5. **Update MemoryCard** with new colors
6. **Update CreateMemoryView** with new colors
7. **Test in light + dark mode**

---

**Status:** Design system complete. Ready for implementation.

Brand vibe: 🌲 Forest premium, not 🍃 stoner kitsch.
