# LifeEase

<p align="center">
  <img src="assets/images/logo.png" alt="LifeEase logo" width="220">
</p>

LifeEase is a Flutter accessibility app for elderly users and children. It combines reminder management, voice interaction, translation support, emergency assistance, Supabase-backed persistence, and SUS usability evaluation in a lightweight mobile-first codebase.

The app is designed around large readable controls, simple navigation, offline-safe reminder storage, and multilingual assistance for English and Tagalog users.

## Target Users

- Elderly users who need readable reminders, voice feedback, emergency access, and low-friction navigation.
- Children or first-time smartphone users who benefit from simple actions, clear language, and guided flows.
- Caregivers or developers validating accessibility-focused reminder workflows.

## Implemented Features

- Email, Google OAuth, anonymous guest, and demo-account sign-in paths through Supabase Auth when configured.
- Reminder creation, local offline persistence with Hive, Supabase upsert/sync support, delete, undo delete, and mark-complete actions.
- Rule-based scheduling engine for medication overlap checks, quiet-hour warnings, study-window suggestions, snooze, and emergency overrides.
- Voice command processing with speech-to-text, local intent parsing, Whisper-ready batch transcription through Supabase Edge Functions, and text-to-speech feedback.
- Translation processing with English/Tagalog offline phrase fallback and Google Translate-ready Edge Function integration.
- Emergency floating action button with contact selection/countdown behavior and tel: launch support.
- Accessibility settings for dark mode, high contrast, large text, sound/vibration preferences, and language switching.
- SUS usability scoring, local result storage, baseline evaluation dialog, and rating interpretation.
- New LifeEase branding across Flutter assets, Android launcher icon, Android splash screen, web icons, login screen, and home header.

## Technology Stack

- Flutter and Dart
- Supabase Auth, Database, Realtime streams, Storage, and Edge Functions
- PostgreSQL schema in `supabase/migrations/001_lifeease_schema.sql`
- Hive for offline reminder and voice-command queue storage
- SharedPreferences for user settings and SUS history
- `speech_to_text` for live speech recognition
- `flutter_tts` for local voice feedback
- Whisper API, Google Translate API, and Inworld TTS integration through `supabase/functions/ai/index.ts`
- `flutter_launcher_icons` and `flutter_native_splash` for Android branding resources

## Project Structure

```text
lib/
├── core/
│   ├── constants/        # Asset and environment constants
│   ├── services/         # Supabase, backend, storage, auth, emergency services
│   ├── themes/           # Light, dark, and high-contrast themes
│   └── utils/            # App exports and route table
├── features/
│   ├── accessibility/    # Login, settings, profile, accessibility UI
│   ├── reminders/        # Home, add reminder, reminder cards and controls
│   ├── scheduling/       # Rule-based scheduling domain logic
│   ├── sus_evaluation/   # SUS scoring and local persistence
│   ├── translation/      # Translation processing module
│   └── voice/            # STT, TTS, Whisper, Inworld, and intent parsing
├── shared/
│   ├── providers/        # Settings and language controllers
│   └── widgets/          # Shared UI components
└── main.dart
```

```text
supabase/
├── functions/ai/index.ts         # transcribe, nlp, translate, and tts actions
└── migrations/001_lifeease_schema.sql
```

## Prerequisites

- Flutter SDK compatible with Dart `^3.9.0`
- Android Studio or VS Code with Flutter tooling
- Android SDK for Android builds
- Supabase project if backend features are required
- Supabase CLI and Deno for Edge Function deployment
- API keys as needed:
  - `OPENAI_API_KEY` for Whisper
  - `GOOGLE_TRANSLATE_API_KEY` for translation
  - `INWORLD_API_KEY` and `INWORLD_TTS_URL` for Inworld TTS

## Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Supabase for runtime builds with Dart defines:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

If these values are not provided, the app still launches and supports guest/offline fallback flows.

3. Apply the database schema:

```bash
supabase db push
```

or run `supabase/migrations/001_lifeease_schema.sql` in the Supabase SQL editor.

4. Deploy the Edge Function:

```bash
supabase functions deploy ai
```

5. Set Edge Function secrets:

```bash
supabase secrets set OPENAI_API_KEY=...
supabase secrets set GOOGLE_TRANSLATE_API_KEY=...
supabase secrets set INWORLD_API_KEY=...
supabase secrets set INWORLD_TTS_URL=...
```

## Running

```bash
flutter run
```

For Android debug validation:

```bash
flutter build apk --debug
```

For release builds:

```bash
flutter build apk --release
```

## Branding

The official logo is stored at:

```text
assets/images/logo.png
```

Android launcher and splash assets are generated from the same file:

```bash
flutter pub run flutter_launcher_icons
flutter pub run flutter_native_splash:create
```

The current configuration intentionally targets Android for generated launcher and splash resources.

## Validation Commands

Run the full local validation sequence before committing:

```bash
flutter clean
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Current validation status:

- `flutter pub get`: passing
- `flutter analyze`: no issues found
- `flutter test`: all tests passing
- `flutter build apk --debug`: passing

## Tests

Focused unit tests live under `test/features/`:

- `scheduling_engine_test.dart`
- `voice_command_processing_module_test.dart`
- `sus_processing_module_test.dart`

These tests cover core non-UI logic for reminder scheduling, voice intent parsing, and SUS scoring.

## Supabase Data Model

The migration creates tables for:

- `users`
- `reminders`
- `schedules`
- `voice_transcripts`
- `translated_texts`
- `emergency_contacts`
- `sus_evaluations`

It also enables row-level security and creates Storage buckets for:

- `audio-recordings`
- `profile-images`

## Edge Function API

The `ai` Edge Function accepts JSON with an `action` field:

```json
{ "action": "transcribe", "fileName": "audio.webm", "languageHint": "en", "audioBase64": [0, 1, 2] }
```

```json
{ "action": "nlp", "text": "remind me to take medicine at 8 AM" }
```

```json
{ "action": "translate", "text": "take medicine", "sourceLanguage": "en", "targetLanguage": "tl" }
```

```json
{ "action": "tts", "text": "Take your medicine now", "speed": 0.95, "volume": 1.0 }
```

If external API keys are missing, the function returns safe fallback responses where possible.

## Accessibility Notes

LifeEase prioritizes:

- Large touch targets
- High contrast mode
- Dark mode
- Text scaling
- Simple bottom navigation
- Voice feedback
- Minimal visual clutter
- Clear snackbar/dialog feedback for actions

## Dependency Policy

Dependencies are kept limited to implemented functionality. Do not add Firebase, camera, charting, animation, ML, or social-login packages unless a feature requires them and the app still passes validation.

Keep these integrations unless intentionally replacing them:

- Supabase
- Hive
- Speech-to-text
- Text-to-speech
- Translation processing
- Whisper/Inworld Edge Function integration
- Accessibility settings

## Developer Notes

- `assets/.env.example` is documentation only. Do not commit real secrets.
- Prefer `--dart-define` for app runtime secrets.
- Keep API secrets in Supabase Edge Function secrets, not in Flutter assets.
- Generated folders such as `build/` and `.dart_tool/` should not be committed.
