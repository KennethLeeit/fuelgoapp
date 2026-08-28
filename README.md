# FuelGo — Flutter App

A Flutter implementation of the FuelGo app based on the provided navigation
structure chart and screen designs.

## Screens included

1. **Login** — email/password sign in
2. **Register** — create account form
3. **Profile** — vehicle preference (EV / Fuel), settings, logout
4. **Home Dashboard** — search, quick access, weekly fuel prices, EV charging
   prices, promo banner
5. **Fuel Station List** — search, filter, sort, favourite toggle
6. **Station Detail** — fuel types, services, address, save/navigate
7. **EV Charger List** — search, filter, sort, availability status
8. **EV Charger Detail** — connector types, charging speed, price, services
9. **Cost Calculator** — Fuel/EV toggle, distance & efficiency inputs,
   estimated cost
10. **Smart Mobility Map** — destination search, Both/Fuel/EV filter,
    simulated map with pins, "Nearest Around You"

Plus a **Favourite** tab that lists everything saved from the fuel station
and EV charger screens.

## Project structure

```
lib/
  main.dart                       # App entry point
  theme/app_theme.dart            # Colors & ThemeData
  models/models.dart              # FuelStation / EVCharger + mock data
  widgets/app_bottom_nav.dart     # Reusable bottom navigation bar
  screens/
    login_screen.dart
    register_screen.dart
    main_nav_screen.dart          # Hosts Home / Map / Favourite / Profile tabs
    home_screen.dart
    fuel_station_list_screen.dart
    station_detail_screen.dart
    ev_charger_list_screen.dart
    ev_charger_detail_screen.dart
    cost_calculator_screen.dart
    smart_mobility_map_screen.dart
    favourite_screen.dart
    profile_screen.dart
```

## Running the app

1. Make sure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
2. **Set up Firebase first** — the app won't build without it since Login/
   Register depend on it. Follow **`FIREBASE_SETUP.md`** (create a free
   Firebase project, run `flutterfire configure`). This generates
   `lib/firebase_options.dart`, which isn't included in this project yet.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run on a connected device / emulator / Chrome:
   ```bash
   flutter run
   ```

## Live fuel prices

The Home screen's "Weekly Fuel Prices" section pulls **real, live data**
from Malaysia's official government Open API (data.gov.my / DOSM) — the same
dataset published as `fuelprice.parquet`:

- Endpoint: `https://api.data.gov.my/data-catalogue?id=fuelprice`
- No API key required.
- Implemented in `lib/services/fuel_price_service.dart`, which fetches the
  full weekly series, takes the latest `series_type: "level"` row for
  RON95 / RON97 / Diesel, and pairs it with the matching `change_weekly` row
  to show the week-over-week arrow.
- Pull-to-refresh or the refresh icon re-fetches; a loading skeleton and a
  retry card handle the loading/error states.

## Maps & navigation

- **Smart Mobility Map** embeds a real interactive map using
  **OpenStreetMap** (via `flutter_map`) — markers for every fuel station
  (orange) and EV charger (green), plus a "you are here" marker. Tapping a
  marker opens a quick-action sheet (view details / navigate); the search
  box does free destination lookup via OSM's Nominatim geocoder.
- **Navigate** buttons on the Station Detail, EV Charger Detail, and map
  pins open turn-by-turn directions in the Google Maps app (or the web) via
  `lib/services/maps_launcher.dart` — this uses Google's Maps URL scheme
  (a deep link, not the Maps SDK), so it needs **no API key**.
- **No API key, no billing account, and no Google Cloud project are needed
  anywhere in this app.** See **`MAP_SETUP.md`** for details on the free
  services used and their fair-use limits.

## Notes

- **Fuel stations and EV chargers are now real, live data** — fetched from
  OpenStreetMap and Open Charge Map near the device's real GPS location
  (falling back to Kuala Lumpur city center if location isn't available).
  See **`LIVE_DATA_SETUP.md`** for details, including the one thing these
  free sources don't have: star ratings (removed from the UI rather than
  faked — neither source tracks that).
- Favouriting a station/charger anywhere in the app (list, detail, or map)
  is tracked by stable id in `lib/services/favourites_service.dart` and
  reflected instantly in the Favourite tab.
- **Login and Register are now backed by real Firebase Authentication +
  Firestore** — see **`FIREBASE_SETUP.md`** for the one-time setup
  (`flutterfire configure`, required before the app will build/run).
  Includes real email/password validation, a live password strength meter
  (8+ characters required; symbols/case are optional but boost the meter),
  and a real "forgot password" reset email.
