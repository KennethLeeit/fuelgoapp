# Map and trip-routing setup

The Smart Mobility Map now runs on **OpenStreetMap** via the `flutter_map`
package instead of the Google Maps SDK. That means:

- OSM tiles and Google Maps navigation links remain keyless.
- Malaysian place search and driving distance use OpenRouteService.
- The OpenRouteService key is held by Firebase Functions, never by Flutter.
- Deploying Firebase Functions requires the Firebase Blaze plan.

The map tiles work after `flutter pub get`; place search and route distance
also require the one-time Firebase Functions setup below.

## What's using what

| Feature | Powered by | Needs a key? |
|---|---|---|
| Embedded interactive map + markers | OpenStreetMap tiles (`tile.openstreetmap.org`) via `flutter_map` | No |
| Malaysian place search | OpenRouteService through Firebase callable functions | Server-side key |
| Trip driving distance | OpenRouteService `driving-car` directions | Server-side key |
| "Navigate" buttons (station/charger detail, map pins) | Google Maps URL scheme (opens the Google Maps app/site the user already has) | No — this is a deep link, not the Maps SDK |

## Fair-use notes (still free, just be a good citizen)

- **Map tiles**: `tile.openstreetmap.org` is OSM's free public server. It's
  meant for light/moderate traffic (dev, small-to-medium apps). If you ever
  ship this to a large audience, OSM's usage policy asks you to either run
  your own tile server or switch to a provider with a paid tile CDN (e.g.
  MapTiler, Stadia Maps, Thunderforest all have generous free tiers too).
  For a personal or small project this default is fine indefinitely.
- The app does not use public Nominatim for autocomplete. Its public usage
  policy forbids client-side autocomplete, so search uses the protected
  OpenRouteService integration instead.
- During development, if the callable backend is unavailable, the app falls
  back to Photon's OSM search-as-you-type/reverse API and OSRM driving routes.
  These are public community/demo services intended for reasonable light
  usage and have no availability guarantee; deploy OpenRouteService for
  production traffic.
- Both are attributed automatically — you'll see a small
  "OpenStreetMap contributors" credit in the corner of the map, which is
  required by OSM's license (ODbL) and is already wired up in the code.

## Running it

```bash
flutter pub get
flutter run
```

Before running route search, upgrade the Firebase project to Blaze, create an
OpenRouteService key, and configure/deploy the backend:

```bash
firebase functions:secrets:set OPENROUTESERVICE_API_KEY
cd functions
npm install
npm test
cd ..
firebase deploy --only functions,firestore
```

The functions are deployed in `asia-southeast1` and require a signed-in
Firebase user. Do not add the OpenRouteService key to Dart source or build
arguments.

No platform-specific config, no `AndroidManifest.xml` meta-data, no
`AppDelegate.swift` edits, no `web/index.html` script tag — all of that was
only needed for Google's Maps SDK, which this app no longer uses for the
embedded map.

## If you ever want Google Maps back

If a client/requirement later demands Google's map tiles specifically
(e.g. for Street View or Google-specific POI data), swap
`lib/screens/smart_mobility_map_screen.dart` back to `google_maps_flutter`
and follow Google's official setup docs for an API key. Everything else in
the app (fuel prices, navigation deep links, favourites, etc.) is unaffected
either way.
