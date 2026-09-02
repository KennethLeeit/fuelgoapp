# Firebase setup — accounts & validation

Login and Register use **real Firebase Authentication** and save account
info to **real Cloud Firestore**. Both are on Firebase's free Spark plan —
no credit card required for what this app uses.

## What's included

- Real email format validation (client-side)
- Password rules: at least 8 characters (symbols/case are optional but
  boost the strength meter)
- Real account creation via Firebase Auth
- Account info saved to Firestore (`users/{uid}`)
- Real login / session persistence
- Real "Forgot Password" reset email
- Vehicle preference synced to your account (saved to Firestore, restored
  automatically on next login)

There is no OTP/email-code verification step — registration goes straight
to the main app after the account is created.

## Setup steps

### 1. Create a Firebase project
1. Go to [console.firebase.google.com](https://console.firebase.google.com).
2. Click **Add project**, give it a name, finish the wizard (Google
   Analytics is optional — skip it if you want the simplest setup).
3. Authentication and Firestore work on Spark. The protected
   OpenRouteService proxy used by map search and the Trip Cost Calculator
   requires upgrading the project to **Blaze** before Functions deployment.

   **If your Google account is managed by a school/work Google Workspace
   organization**, you may hit a policy blocking new Firebase/Google Cloud
   project creation. Try a personal Google account instead, or ask your
   org admin. If that's not an option, Supabase is a good free
   alternative that isn't tied to Google Cloud at all — ask if you want
   the backend swapped to that instead.

### 2. Enable Email/Password sign-in
1. In the Firebase console, go to **Build → Authentication → Sign-in method**.
2. Click **Email/Password**, enable it, save.

### 3. Create a Firestore database
**This step is required** — skipping it is the most common cause of a
"Something went wrong" error when registering (see Troubleshooting below).

1. Go to **Build → Firestore Database → Create database**.
2. Start in **production mode** (recommended) or test mode — either works
   for development.
3. Pick any region close to you.
4. Once created, go to the **Rules** tab and use something like:
   ```bash
   firebase deploy --only firestore
   ```
   The checked-in `firestore.rules` covers user profiles, owned vehicles,
   owned saved routes, and public reviews. `firestore.indexes.json` contains
   the indexes used by their live queries.

   If the Firebase project already has additional live collections or rule
   clauses, merge those into `firestore.rules` before deploying. A rules
   deployment replaces the active ruleset; it cannot discover and preserve
   console-only rules automatically.

### 4. Connect the Flutter app (FlutterFire CLI)
This generates `lib/firebase_options.dart`, which `main.dart` already
imports — the app won't build until this file exists.

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

- Select the Firebase project you just created.
- Select the platforms you want (Android/iOS/Web/etc.).
- This automatically creates `lib/firebase_options.dart` and any needed
  native config files (`google-services.json`, `GoogleService-Info.plist`).

### 5. Run it

```bash
flutter pub add firebase_core
flutter pub add firebase_auth
flutter pub add cloud_firestore
flutter pub add cloud_functions
flutter pub get
flutter run
```

### 6. Configure route functions

Create an OpenRouteService developer key, then keep it in Firebase Secret
Manager and deploy the callable functions:

```bash
firebase functions:secrets:set OPENROUTESERVICE_API_KEY
cd functions
npm install
npm test
cd ..
firebase deploy --only functions
```

The Functions deployment requires Blaze. The API key must never be committed
or placed directly in the Flutter application.

## Troubleshooting

**"Something went wrong: ..." on Register/Login** — the app now shows the
*real* underlying error message instead of a generic one, so read what
follows "Something went wrong:" or "Firebase error:" — it tells you
exactly what failed. Common causes:

- **Firestore database not created yet** (Step 3 above skipped) — you'll
  see a Firestore-related error. Note: as of this version, a Firestore
  write failure during registration no longer blocks account creation —
  the Firebase Auth account still gets created and you can still sign in,
  even if the profile document didn't save. Fix Firestore setup and the
  next save attempt (e.g. changing Vehicle Preference) will work.
- **`operation-not-allowed` / `configuration-not-found`** — Email/Password
  sign-in isn't enabled yet (Step 2 above skipped).
- **`network-request-failed`** — check your internet connection, or that
  `flutterfire configure` actually completed and `firebase_options.dart`
  has real (not placeholder) values.

**Registering/logging in works, but every save afterwards fails with
"permission-denied"** (changing Vehicle Preference, favouriting a station,
changing your name) — this means your Firestore Rules only allow
*creating* a document, not *updating* one that already exists. This is
easy to do by accident if your rules split `allow create` and
`allow update` into separate conditions and only wrote one of them. Go to
**Firestore Database → Rules** and make sure you have the single combined
rule from Step 3 above — `allow read, write: if request.auth != null &&
request.auth.uid == userId;` — which covers create, update, *and* delete
in one line, rather than trying to list them separately. Click **Publish**
after editing; rule changes can take a minute to take effect.

## Password rules

Enforced in `lib/utils/validators.dart`:
- At least 8 characters (only hard requirement)
- The strength meter additionally rewards length ≥ 12, a symbol, and
  character variety (upper/lower/digit mix) — none of these are required
  to register, they just move the meter from "Weak" toward "Strong."

## Account data stored in Firestore

Each user gets a document at `users/{uid}` with:
```
fullName, email, createdAt, drivesFuel, drivesEV
```
`drivesFuel`/`drivesEV` mirror the Vehicle Preference toggle on the Profile
screen — changing it there updates Firestore immediately, and it's
restored automatically the next time that account logs in.

Vehicles live in top-level `vehicles` documents tagged with `userId`. Saved
routes follow the same established pattern in top-level `savedRoutes`
documents. Calculated costs and historical prices are deliberately not saved.
