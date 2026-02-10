# Stride iOS App

A beautiful, native iOS app for AI-powered running training plans.

## Features

- **Intelligent Onboarding**: Multi-step onboarding flow matching the web experience
- **AI-Generated Plans**: Connect to the FastAPI backend for personalized training plans
- **Accordion Plan View**: Expandable weeks with day-by-day workout cards
- **Workout Tracking**: Mark workouts as complete with progress visualization
- **Cloud Sync**: iCloud/CloudKit sync across all your devices
- **Beautiful UI**: Dark theme with modern design and smooth animations

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Active Apple Developer account (for CloudKit)

## Setup

### 1. Open in Xcode

Open `StrideApp.xcodeproj` in Xcode (or create a new project and add all the Swift files).

### 2. Configure Bundle Identifier

Update the bundle identifier in your project settings:
- Select the project in Navigator
- Select the target
- Change Bundle Identifier to your own (e.g., `com.yourname.stride`)

### 3. Enable Capabilities

In Xcode, go to your target's "Signing & Capabilities" tab and add:
- **iCloud** (check CloudKit)
- **Background Modes** (check Remote notifications)

### 4. Configure Backend URL

Update the API base URL in `Services/APIService.swift`:

```swift
init(baseURL: String = "http://YOUR_SERVER_IP:8000") {
    self.baseURL = baseURL
}
```

For local development:
- iOS Simulator: Use `http://localhost:8000`
- Physical device: Use your Mac's IP address (e.g., `http://192.168.1.100:8000`)

### 5. Run the FastAPI Backend

Make sure the FastAPI backend is running:

```bash
cd /path/to/Stride\ v.2
source venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 6. Build and Run

Select your target device/simulator and press ⌘R to build and run.

## Project Structure

```
StrideApp/
├── App/
│   ├── StrideApp.swift         # App entry point
│   ├── ContentView.swift       # Root view
│   └── Theme.swift             # Colors, fonts, styles
├── Models/
│   ├── Enums.swift             # RaceType, FitnessLevel, etc.
│   ├── TrainingPlan.swift      # SwiftData model
│   ├── Week.swift              # SwiftData model
│   ├── Workout.swift           # SwiftData model
│   └── APIModels.swift         # Request/response types
├── Views/
│   ├── Onboarding/             # Onboarding flow views
│   ├── Plan/                   # Plan display views
│   ├── Components/             # Reusable UI components
│   └── Settings/               # Settings views
├── ViewModels/
│   ├── OnboardingViewModel.swift
│   └── PlanViewModel.swift
├── Services/
│   ├── APIService.swift        # FastAPI communication
│   ├── PlanParser.swift        # Parse AI response
│   └── SyncService.swift       # CloudKit sync
├── Utilities/
│   └── Extensions.swift        # Helper extensions
└── Assets.xcassets/            # App icons, colors
```

## Architecture

- **SwiftUI**: Declarative UI framework
- **SwiftData**: Persistent storage with CloudKit sync
- **MVVM**: Model-View-ViewModel architecture
- **Async/Await**: Modern Swift concurrency

## API Endpoints

The app communicates with these FastAPI endpoints:

- `POST /api/analyze-conflicts` - Analyze user profile for conflicts
- `POST /api/generate-plan` - Generate training plan (streaming response)

## Customization

### Colors

Edit `App/Theme.swift` to customize the color palette:

```swift
extension Color {
    static let strideOrange = Color(red: 1.0, green: 0.45, blue: 0.25)
    // ... other colors
}
```

### App Icon

Replace the placeholder in `Assets.xcassets/AppIcon.appiconset/` with your 1024x1024 app icon.

## Troubleshooting

### Network Errors

- Ensure the FastAPI server is running and accessible
- Check `Info.plist` has `NSAppTransportSecurity` configured for local development
- For physical devices, use your Mac's local IP address

### CloudKit Sync

- Ensure you're signed into iCloud on the device
- Check that iCloud capability is properly configured
- CloudKit containers may take a few minutes to provision

## License

MIT License - See LICENSE file for details
