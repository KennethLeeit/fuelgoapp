# Live location data — free APIs used

Fuel stations and EV chargers are now **real, live data** — no more mock
list, and **nothing in this app requires any signup, account, or API key**.
Both use OpenStreetMap's free Overpass API.

## Fuel stations — OpenStreetMap (Overpass API)

- `lib/services/osm_fuel_service.dart`
- Free, keyless, no signup: `https://overpass-api.de/api/interpreter`
- Returns real fuel stations near a coordinate: name, brand, address,
  opening hours (when tagged), and any services tagged on the node
  (shop, toilets, car wash, ATM, LPG).
- **No star ratings** — OpenStreetMap doesn't track those. The rating row
  was removed from the UI rather than faked.
- Fuel types (RON95/RON97/Diesel) fall back to Malaysia's typical default
  when a station doesn't explicitly tag which fuels it sells, since most
  stations don't tag this on OSM.

## EV chargers — OpenStreetMap (Overpass API)

- `lib/services/osm_ev_charger_service.dart`
- Free, keyless, **no registration or account of any kind** —
  `amenity=charging_station` nodes on the same Overpass API already used
  for fuel stations, with the same 3-mirror fallback for reliability.
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

*(This app previously used Open Charge Map for EV chargers, which now
requires a free account + API key for every request. Switched to
OpenStreetMap instead so nothing in this app needs any signup at all.)*

## Location — real GPS with automatic fallback

- `lib/services/location_service.dart`
- Uses the `geolocator` package to request the device's real location.
- If location services are off, permission is denied, or anything else
  goes wrong (desktop without GPS, indoor timeout, etc.), it **silently
  falls back to Kuala Lumpur city center** rather than showing an error —
  the app stays usable either way.
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

Both Overpass and Nominatim (used for map search) are free public services
meant for light/moderate traffic — fine for personal or small-scale apps
indefinitely. Don't hammer them with automated bulk requests. See
`MAP_SETUP.md` for the map-tile side of this same fair-use note.

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
