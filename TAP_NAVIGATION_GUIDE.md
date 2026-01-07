# Reader Tap Navigation - Visual Guide

## Screen Layout

```
┌─────────────────────────────────────────────┐
│                                             │
│  ◄─────────┐     NO ACTION    ┌─────────►  │
│            │                  │             │
│   PREVIOUS │                  │    NEXT    │
│    PAGE/   │                  │   PAGE/    │
│  CHAPTER   │                  │  CHAPTER   │
│            │                  │             │
│            │                  │             │
│   [30%]    │      [40%]       │   [30%]    │
│            │                  │             │
│  Tap here  │   Text selection │  Tap here  │
│  to go     │   and scrolling  │  to go     │
│  backward  │   work here      │  forward   │
│            │                  │             │
└─────────────────────────────────────────────┘
```

## How It Works

### Zone Distribution
- **Left Zone (0-30%)**: Previous page/chapter
- **Center Zone (30-70%)**: No tap action - preserves reading interactions
- **Right Zone (70-100%)**: Next page/chapter

### Why This Layout?

1. **Natural Reading Flow**: Matches left-to-right reading pattern
2. **Easy Thumb Access**: Comfortable for one-handed use
3. **Accident Prevention**: Center zone prevents accidental page changes
4. **Text Selection**: Center zone allows selecting and copying text
5. **Tablet Friendly**: Larger zones on bigger screens are easier to hit

## Usage Examples

### Phone (Small Screen)
```
Screen width: 360px
- Left zone:   0px - 108px   (previous)
- Center zone: 108px - 252px (no action)
- Right zone:  252px - 360px (next)
```

### Tablet (Large Screen)
```
Screen width: 1024px
- Left zone:   0px - 307px   (previous)
- Center zone: 307px - 717px (no action)
- Right zone:  717px - 1024px (next)
```

## Alternative Navigation Methods

The tap zones complement (don't replace) existing navigation:

1. **Arrow Buttons** (PDF only): In the app bar
2. **Swipe Gestures** (PDF): Horizontal swipe to change pages
3. **Table of Contents** (EPUB): Drawer menu for chapter navigation
4. **Scroll/Swipe** (EPUB): Natural scrolling within chapters

## Tips for Users

- **For precision**: Use arrow buttons in the app bar
- **For quick navigation**: Tap left/right sides of screen
- **For chapter jumping**: Use table of contents (EPUB)
- **For reading**: Center zone is safe for text selection and scrolling
