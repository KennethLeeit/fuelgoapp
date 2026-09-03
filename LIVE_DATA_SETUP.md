# Live location data — free APIs used

Fuel stations and EV chargers are real nearby data. Station data uses the
sources below; place search and trip routing are documented separately in
`MAP_SETUP.md` and require the protected OpenRouteService setup.

## Fuel stations — OpenStreetMap (Overpass API)

- `lib/services/osm_fuel_service.dart`
- Free, keyless, no signup: `https://overpass-api.de/api/interpreter`
- Returns real fuel stations near a coordinate: name, brand, address,
  opening hours (when tagged), and any services tagged on the node
  (shop, toilets, car wash, ATM, LPG).
- **No star ratings** — OpenStreetMap doesn't track those. The rating row
  was removed from the UI rather than faked.
- Fuel types are only shown as verified when the source explicitly supplies
  them. Missing fuel tags remain unknown rather than being guessed.

## EV chargers — OpenStreetMap with optional Open Charge Map

- `lib/services/osm_ev_charger_service.dart` is the keyless source used by
  default for both Nearby and Along Route searches.
- `lib/services/open_charge_map_service.dart` becomes the primary source only
  when an Open Charge Map API key is configured; OSM remains its fallback.
- Open Charge Map currently rejects anonymous requests, so the app skips that
  known-failing request instead of allowing cached and fresh screens to show
  inconsistent results.
- Returns real chargers near a coordinate: operator, connector types (Type
  2, CCS2, CHAdeMO, Tesla, etc. — read from OSM's `socket:*` tags), max
  power in kW when tagged, and address.
- **No star ratings** — same as fuel stations, OSM doesn't track those.
- Pricing shows "Free" / "Paid — check operator app" based on OSM's `fee`
  tag when present, otherwise omitted — real per-kWh pricing isn't
  published in open data anywhere for free (see the EV pricing note on the
  Home screen, which is separately labeled as indicative).
- Coverage is community-contributed, so it's typically strong in cities and
  patchier in rural areas — same caveat as the fuel station data.

## Location — real GPS with explicit failure states

- `lib/services/location_service.dart`
- Uses the `geolocator` package to request the device's real location.
- If location services are off, permission is denied, or a fix times out,
  the app shows a clear error and offers retry/manual place search. It does
  not pretend Kuala Lumpur is the user's current position.
- Platform permissions needed once you run `flutter create .`:
  - **Android**: `flutter create .` already adds
    `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` via the `geolocator`
    plugin's manifest merge — no manual edit needed in most cases.
  - **iOS**: add `NSLocationWhenInUseUsageDescription` to
    `ios/Runner/Info.plist` with a short reason string, e.g. "Used to show
    nearby fuel stations and EV chargers."
  - **Web**: the browser prompts automatically; no config needed.

## Favourites

Since station/charger lists are now fetched live instead of coming from a
fixed mock array, favouriting works by **stable id** instead of mutating an
object in a list (`lib/services/favourites_service.dart`, in-memory only —
swap in `shared_preferences` or a backend call if you want it to persist
across app restarts). The Favourite tab re-fetches nearby places and shows
whichever ones are currently favourited, so a favourite will only appear
there while it's within that fetch's search radius (20 km) — this is a
limitation of not having a backend to store full favourited records
independent of location.

## Fair use

Overpass is a free public service intended for light/moderate traffic. Place
search no longer uses public Nominatim autocomplete; see `MAP_SETUP.md` for
the protected OpenRouteService configuration and map-tile fair-use notes.

## Reliability & map controls

- **Multiple Overpass mirrors**: `osm_fuel_service.dart` tries three public
  Overpass instances in order (kumi.systems, overpass-api.de,
  openstreetmap.ru) and falls through automatically if one is down or
  rate-limited, rather than failing outright.
- **Independent failure handling**: on the Smart Mobility Map, a failure in
  the fuel-station fetch no longer blanks out the EV-charger results (and
  vice versa) — each source loads and errors independently, with a small
  banner noting which one is temporarily unavailable. The old behavior
  (both showing "None nearby" if only one source failed) is fixed.
- **Viewport-only markers**: the map now only renders markers that are
  currently visible on screen, decluttering it as you pan/zoom, instead of
  dumping every fetched result on the map at once.
- **Zoom controls**: explicit +/− buttons in the bottom-right of the map
  (in addition to scroll-wheel/pinch, which already worked).
- **Browse by state**: the filter (tune) icon and the "State" button open a
  picker with the 13 states of Malaysia plus the Federal Territory of Kuala
  Lumpur (commonly referred to together as "14 states"). Picking one
  re-centers the map and re-fetches nearby stations/chargers around that
  state's center — same free APIs, just a different search origin instead
  of your GPS location.
- **Along Route**: route geometry is displayed as a line and live candidates
  are ranked within a 5 km or 10 km corridor. Requests are made in small
  batches and results are deduplicated. Open Charge Map/OSM do not provide
  reliable live occupancy or vehicle compatibility, so the UI does not make
  those claims.
