# Reader Navigation Feature

## Overview
The built-in EPUB and PDF readers now support intuitive tap-based navigation in addition to the existing arrow buttons and swipe gestures.

## How It Works

### Tap Zones
The screen is divided into three horizontal zones:
- **Left Zone (0-30%)**: Tap to go to previous page/chapter
- **Center Zone (30-70%)**: No tap action - preserves text selection and scrolling
- **Right Zone (70-100%)**: Tap to go to next page/chapter

### Implementation

#### EPUB Reader (`lib/ui/epub_viewer.dart`)
The `_buildTapNavigationWrapper()` method wraps the EpubView widget with a GestureDetector:
- Uses `onTapUp` to capture tap events
- Calculates tap position relative to screen width using `MediaQuery`
- Calls `_epubReaderController.previousChapter()` or `nextChapter()` based on zone
- Center zone has no action to allow text selection and other interactions

#### PDF Reader (`lib/ui/pdf_viewer.dart`)
Similar implementation wrapping the PDFView widget:
- Uses same 30-40-30 zone split
- Calls `_goToPreviousPage()` or `_goToNextPage()` helper methods
- Maintains existing swipe horizontal navigation
- Arrow buttons in AppBar remain functional

### Design Rationale

1. **30-40-30 Split**: Provides a good balance between:
   - Easy tap targets for navigation (especially on tablets)
   - Sufficient center space for text selection and content interaction
   
2. **GestureDetector Approach**: 
   - Simple and clean implementation
   - Less intrusive than overlay Stack widgets
   - Doesn't interfere with underlying widget gestures

3. **Maintaining Existing Features**:
   - Arrow buttons still work (especially useful for precise control)
   - Swipe gestures remain functional on PDF reader
   - Text selection in EPUB reader still works in center zone

## Tablet Support
The implementation automatically scales to larger screens:
- Tap zones are percentage-based, so they work on any screen size
- Larger screens provide bigger tap targets
- Center zone scales proportionally for comfortable reading

## Future Enhancements
If you want to extend this feature in the future, consider:
- Adding settings to customize zone sizes (e.g., 25-50-25 or 33-33-33)
- Adding visual feedback when tapping (subtle animation or haptic feedback)
- Making tap navigation optional via settings toggle
- Supporting vertical tap zones for vertical scrolling modes
