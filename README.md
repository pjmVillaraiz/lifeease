# LifeEase – Accessible Reminder & Assistance App

LifeEase is a Flutter-based mobile application designed to assist elderly users and children in managing daily reminders, tasks, and essential information with a focus on simplicity, accessibility, and usability.

The application provides an intuitive interface with clear layouts, readable text, and customizable settings such as dark mode, language switching, and accessibility options.

---

## Key Features

### Core Functionality

* Create and manage reminders
* Custom reminder lead times
* Emergency contacts access
* User profile management

---

### Settings (Functional)

#### Notifications

* Enable or disable reminders
* Control sound and vibration

#### Accessibility

* Large text mode for improved readability
* High contrast mode for better visibility

#### Appearance

* Dark mode toggle applied globally

#### Language

* English and Filipino (Tagalog) switching
* Updates UI dynamically across supported screens

#### About

* App version display
* Privacy Policy (placeholder)
* Help and Support (placeholder)

---

## State Management

The application uses a lightweight global state approach:

* ValueNotifier for:

  * Language switching
  * Theme (dark mode)
  * Accessibility settings

This enables real-time UI updates across multiple screens without complex state management frameworks.

---

## Prerequisites

* Flutter SDK (^3.38.4)
* Dart SDK
* Android Studio or VS Code with Flutter extensions
* Android SDK or Xcode (for iOS development)

---

## Installation

```bash
flutter pub get
```

---

## Running the Application

```bash
flutter run
```

### Running on an Emulator

```bash
flutter emulators
flutter emulators --launch <emulator_id>
flutter run
```

---

## Project Structure

```
flutter_app/
├── android/            
├── ios/                
├── lib/
│   ├── core/           
│   ├── presentation/   
│   ├── routes/         
│   ├── theme/          
│   ├── widgets/        
│   └── main.dart       
├── assets/             
├── pubspec.yaml        
└── README.md           
```

---

## Navigation

Screens are opened using:

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => Screen()),
);
```

This ensures proper back navigation and a consistent user experience.

---

## Theming

The application supports both light and dark themes:

```dart
ThemeData theme = Theme.of(context);
```

Theme changes are applied globally through the settings screen.

---

## Responsive Design

The application uses the Sizer package for responsive layouts:

```dart
width: 50.w
height: 20.h
```

This ensures compatibility across different screen sizes and devices.

---

## Build for Production

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

---

## Future Improvements

* Integration of local notifications
* Full localization using the intl package
* Persistent settings using local storage
* Cloud synchronization for reminders

---

## Developer Notes

This project emphasizes accessible user interface design, making it suitable for:

* Elderly users
* Children
* First-time smartphone users

---

LifeEase is designed to simplify daily routines through accessible and user-friendly mobile interactions.
