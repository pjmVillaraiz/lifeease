# LifeEase

<p align="center">
  <img src="assets/images/logo.png" alt="LifeEase logo" width="220">
</p>

## Project Overview

LifeEase is a comprehensive, accessibility-first mobile application designed specifically for elderly users and children. The application combines intuitive reminder management, advanced voice interaction, language translation, emergency assistance, and Supabase-backed persistence. Developed entirely in Flutter, it focuses on delivering a lightweight, stable, and highly accessible user experience.

## Objectives

- Provide a zero-friction interface for managing daily health and activity reminders.
- Enable hands-free operation through robust voice command processing (Speech-to-Text and Text-to-Speech).
- Support multilingual users with seamless English and Tagalog integration.
- Ensure high usability through continuous System Usability Scale (SUS) evaluation integration.
- Maintain a secure, clean, and scalable architecture using Supabase and local persistence.

## Implemented Modules

1. **Voice Command Processing Module:** Leverages lightweight NLP logic alongside OpenAI Whisper for accurate intent recognition.
2. **Translation Module:** Provides instant English ↔ Tagalog text conversion to assist multilingual households.
3. **Scheduling Engine:** A robust, rule-based scheduling system (inspired by enterprise workflow constraints) that manages overlaps and quiet hours.
4. **Accessibility System:** Deep integration of large touch targets, high contrast modes, and text scaling.
5. **Emergency Module:** Rapid-access floating action button connected to key contacts.
6. **SUS Evaluation Module:** Built-in usability scoring mechanisms to continuously validate app effectiveness.

## Architecture Overview

LifeEase follows a strict feature-based Clean Architecture pattern:
- **`core/`**: Contains environment configurations, overarching themes, global routing, and external service clients (Supabase, offline sync).
- **`features/`**: Houses domain-specific logic and UI (reminders, voice, translation, scheduling, accessibility).
- **`shared/`**: Contains highly reusable UI widgets and state providers.

## Prerequisites

- Flutter SDK (compatible with Dart `^3.9.0`)
- Android Studio or Visual Studio Code
- Android Emulator or connected physical device
- Supabase Project (for backend synchronization)
- API Keys:
  - OpenAI (Whisper)
  - Google Web Client ID
  - Supabase URL & Anon Key
  - Inworld TTS (Optional)

## Installation

1. Clone the repository to your local machine.
2. Run the following command to fetch dependencies:
   ```bash
   flutter pub get
   ```

## Environment & API Setup

LifeEase utilizes an `env.json` file for secure environment variable injection. 

1. Locate the `env.example.json` file in the root directory.
2. Copy it and rename it to `env.json`.
3. Fill in your actual keys:
   ```json
   {
       "SUPABASE_URL": "your_supabase_url_here",
       "SUPABASE_ANON_KEY": "your_supabase_anon_key_here",
       "OPENAI_API_KEY": "your-openai-api-key-here",
       "GEMINI_API_KEY": "your-gemini-api-key-here",
       "GOOGLE_WEB_CLIENT_ID": "your_google_web_client_id"
   }
   ```
> **Security Note:** `env.json` is explicitly ignored in version control (`.gitignore`). Never commit your production keys.

## Supabase Setup

1. Create a new Supabase project.
2. Run the provided database schema:
   ```bash
   supabase db push
   ```
   *(Or manually execute `supabase/migrations/001_lifeease_schema.sql` in your Supabase SQL editor).*
3. Deploy the Edge Functions for AI processing:
   ```bash
   supabase functions deploy ai
   ```
4. Bind your API secrets to your Supabase project:
   ```bash
   supabase secrets set OPENAI_API_KEY=your_key
   ```

## Emulator Setup

1. Open Android Studio and launch an AVD (Android Virtual Device).
2. Ensure the emulator has internet access and Google Play Services updated.
3. Run `flutter devices` to ensure the emulator is recognized.

## Running Instructions

To launch the application on your connected device or emulator in debug mode:
```bash
flutter run
```

To build a release APK for Android:
```bash
flutter build apk --release
```

## Troubleshooting

- **Analyzer Errors:** If you experience unresolved dependencies, run `flutter clean` followed by `flutter pub get`.
- **Missing API Keys:** Ensure `env.json` is properly formatted as a JSON file and resides in the project root. If the app crashes on launch, verify the JSON structure.
- **Supabase Sync Failing:** Verify your `SUPABASE_URL` and `SUPABASE_ANON_KEY` are correct. Ensure your Edge Functions are successfully deployed.

## Testing

LifeEase includes unit tests for core logical processing. To execute the test suite:
```bash
flutter test
```
*Current test coverage focuses on the scheduling engine, voice processing module, and SUS evaluation module.*

## Project Structure

```text
lib/
├── core/
│   ├── constants/
│   ├── services/
│   ├── themes/
│   └── utils/
├── features/
│   ├── accessibility/
│   ├── reminders/
│   ├── scheduling/
│   ├── sus_evaluation/
│   ├── translation/
│   └── voice/
├── shared/
│   ├── providers/
│   └── widgets/
└── main.dart
```

## Accessibility Features

- **Readability:** High contrast themes and dynamic text scaling.
- **Navigation:** Simplified bottom navigation avoiding nested menus.
- **Touch Targets:** Minimum 48x48 logical pixels for all interactive elements.
- **Cognitive Load:** Straightforward visual cues and Voice-Assisted interactions.

## Security Notes

- **Environment variables** are managed locally via `env.json`.
- **Supabase connection** strictly utilizes the Publishable `anon` key on the client side.
- Sensitive business logic and external API interactions (OpenAI, Inworld) must be executed server-side via **Supabase Edge Functions**.

## Future Improvements

- Add iOS deployment support and Apple Health integration.
- Implement more robust offline queues for syncing voice transcripts when the network drops.
- Introduce deeper analytics for SUS evaluation scores over time.
- Enhance the AI natural language parsing for complex, multi-step voice commands.
