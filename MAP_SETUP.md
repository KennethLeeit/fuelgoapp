# Map setup — no API key needed

The Smart Mobility Map now runs on **OpenStreetMap** via the `flutter_map`
package instead of the Google Maps SDK. That means:

- **No API key**
- **No Google Cloud project**
- **No billing account / credit card**
- **No usage cap** for a normal app's traffic

It works out of the box the moment you run `flutter pub get`.

## What's using what

| Feature | Powered by | Needs a key? |
|---|---|---|
| Embedded interactive map + markers | OpenStreetMap tiles (`tile.openstreetmap.org`) via `flutter_map` | No |
| "Search destination" box | OSM's free Nominatim geocoder | No |
| "Navigate" buttons (station/charger detail, map pins) | Google Maps URL scheme (opens the Google Maps app/site the user already has) | No — this is a deep link, not the Maps SDK |

## Fair-use notes (still free, just be a good citizen)

- **Map tiles**: `tile.openstreetmap.org` is OSM's free public server. It's
  meant for light/moderate traffic (dev, small-to-medium apps). If you ever
  ship this to a large audience, OSM's usage policy asks you to either run
  your own tile server or switch to a provider with a paid tile CDN (e.g.
  MapTiler, Stadia Maps, Thunderforest all have generous free tiers too).
  For a personal or small project this default is fine indefinitely.
- **Nominatim search**: also OSM's free service, rate-limited to ~1 request/
  second per app. `fuel_price... / maps_launcher` code already sends a
  descriptive `User-Agent` header as required by their usage policy. Don't
  hammer it with bulk/automated lookups.
- Both are attributed automatically — you'll see a small
  "OpenStreetMap contributors" credit in the corner of the map, which is
  required by OSM's license (ODbL) and is already wired up in the code.

## Running it

```bash
flutter pub get
flutter run
```

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
