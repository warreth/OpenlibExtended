# Instance Management Feature

This feature adds support for multiple Anna's Archive mirrors and custom instances with automatic failover.

## Features

### Default Instances
The app comes pre-configured with 7 default instances:
- Anna's Archive (.org) - https://annas-archive.org
- Anna's Archive (.gs) - https://annas-archive.gs
- Anna's Archive (.se) - https://annas-archive.se
- Anna's Archive (.li) - https://annas-archive.li
- Anna's Archive (.st) - https://annas-archive.st
- Anna's Archive (.pm) - https://annas-archive.pm
- Welib.org - https://welib.org

### Automatic Failover
- The app tries each enabled instance up to 2 times before moving to the next
- Instances are tried in priority order (can be customized)
- If all instances fail, an error is shown

### Instance Management
Users can:
1. **Select current instance**: Choose which instance to use by default from the Settings page
2. **Enable/Disable instances**: Toggle which instances are active
3. **Reorder priority**: Drag and drop to change the order in which instances are tried
4. **Add custom instances**: Add your own mirror URLs
5. **Delete custom instances**: Remove custom mirrors (default instances cannot be deleted)
6. **Reset to defaults**: Restore the original instance list

## Usage

### Selecting an Instance
1. Go to Settings page
2. Find the "Archive Instance" section
3. Use the dropdown to select your preferred instance

### Managing Instances
1. Go to Settings page
2. Tap "Manage Instances"
3. You can:
   - Drag items to reorder priority
   - Toggle switches to enable/disable instances
   - Tap the + icon to add custom instances
   - Tap the trash icon to delete custom instances
   - Tap the refresh icon to reset to defaults

### Adding a Custom Instance
1. In the Manage Instances page, tap the + icon
2. Enter a name (e.g., "My Custom Mirror")
3. Enter the base URL (e.g., "https://example.com")
4. Tap "Add"

## Technical Details

### Files Modified/Created
- `lib/services/instance_manager.dart` - Instance management service
- `lib/services/annas_archieve.dart` - Updated to use configurable instances
- `lib/ui/instances_page.dart` - UI for managing instances
- `lib/ui/settings_page.dart` - Added instance selector
- `lib/state/state.dart` - Added instance providers

### Data Storage
Instance configuration is stored in the app's database using SharedPreferences-style storage.

### Retry Logic
The retry mechanism is implemented in `AnnasArchieve._requestWithRetry()`:
1. Gets list of enabled instances sorted by priority
2. For each instance:
   - Tries the request up to `maxRetries` times (currently 2)
   - Waits 500ms between retries on the same instance
3. If all instances fail, throws the last exception

## Configuration

### Changing Retry Count
To modify how many times each instance is tried, edit `maxRetries` in `lib/services/annas_archieve.dart`:

```dart
static const int maxRetries = 2; // Change this value
```

### Changing Retry Delay
To modify the delay between retries, edit `retryDelayMs` in `lib/services/annas_archieve.dart`:

```dart
static const int retryDelayMs = 500; // Delay in milliseconds
```

### Adding More Default Instances
Edit `_defaultInstances` in `lib/services/instance_manager.dart`:

```dart
static final List<ArchiveInstance> _defaultInstances = [
  // ... existing instances ...
  ArchiveInstance(
    id: 'your_unique_id',
    name: 'Display Name',
    baseUrl: 'https://your-mirror.com',
    priority: 7, // Next priority number
    enabled: true,
  ),
];
```

## Future Enhancements
Potential improvements:
- Instance health monitoring
- Automatic instance testing/ranking
- Instance response time display
- Import/export instance configurations
- Community-shared instance lists
