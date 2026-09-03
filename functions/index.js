const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {
  ContractError,
  malaysiaCoordinate,
  malaysiaQuery,
  placeFromFeature,
  pointsAreTooClose,
  routeCoordinatesFromGeoJson,
} = require("./ors_contract");

initializeApp();

const orsApiKey = defineSecret("OPENROUTESERVICE_API_KEY");
const callableOptions = {
  region: "asia-southeast1",
  timeoutSeconds: 20,
  maxInstances: 4,
  secrets: [orsApiKey],
};

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to use route services.");
  }
}

function validate(callback) {
  try {
    return callback();
  } catch (error) {
    if (error instanceof ContractError) {
      throw new HttpsError(error.code, error.message);
    }
    throw error;
  }
}

async function orsGet(path, params) {
  const url = new URL(`https://api.heigit.org${path}`);
  url.searchParams.set("api_key", orsApiKey.value());
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, String(value));
  }
  let response;
  try {
    response = await fetch(url, {signal: AbortSignal.timeout(12000)});
  } catch (_) {
    throw new HttpsError("unavailable", "Location provider is unavailable.");
  }
  if (response.status === 429) {
    throw new HttpsError("resource-exhausted", "Location provider quota reached.");
  }
  if (!response.ok) {
    throw new HttpsError("unavailable", `Location provider returned ${response.status}.`);
  }
  return response.json();
}

exports.searchMalaysiaPlaces = onCall(callableOptions, async (request) => {
  requireAuth(request);
  const query = validate(() => malaysiaQuery(request.data));
  const result = await orsGet("/pelias/v1/search", {
    text: query,
    "boundary.country": "MY",
    size: 6,
  });
  const places = (result.features || [])
      .map(placeFromFeature)
      .filter(Boolean)
      .slice(0, 6);
  return {places};
});

exports.reverseMalaysiaPlace = onCall(callableOptions, async (request) => {
  requireAuth(request);
  const point = validate(() => malaysiaCoordinate(request.data));
  const result = await orsGet("/pelias/v1/reverse", {
    "point.lat": point.latitude,
    "point.lon": point.longitude,
    "boundary.country": "MY",
    size: 1,
  });
  const place = (result.features || []).map(placeFromFeature).find(Boolean);
  if (!place) {
    throw new HttpsError("not-found", "Current location is outside Malaysia or could not be identified.");
  }
  return place;
});

exports.calculateMalaysiaRoute = onCall(callableOptions, async (request) => {
  requireAuth(request);
  const from = validate(() => malaysiaCoordinate(request.data?.from));
  const to = validate(() => malaysiaCoordinate(request.data?.to));
  if (pointsAreTooClose(from, to)) {
    throw new HttpsError("invalid-argument", "Starting point and destination are too close together.");
  }

  let response;
  try {
    response = await fetch(
        "https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson",
        {
          method: "POST",
          headers: {
            Authorization: orsApiKey.value(),
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            coordinates: [
              [from.longitude, from.latitude],
              [to.longitude, to.latitude],
            ],
            instructions: false,
          }),
          signal: AbortSignal.timeout(15000),
        },
    );
  } catch (_) {
    throw new HttpsError("unavailable", "Routing provider is unavailable.");
  }
  if (response.status === 429) {
    throw new HttpsError("resource-exhausted", "Routing provider quota reached.");
  }
  if (!response.ok) {
    const code = response.status === 404 || response.status === 400 ? "not-found" : "unavailable";
    throw new HttpsError(code, "No driving route could be calculated for those locations.");
  }
  const result = await response.json();
  const summary = result?.features?.[0]?.properties?.summary;
  const distance = Number(summary?.distance);
  const duration = Number(summary?.duration);
  if (!Number.isFinite(distance) || distance <= 0) {
    throw new HttpsError("not-found", "No driving route could be calculated for those locations.");
  }
  const routeCoordinates = validate(() => routeCoordinatesFromGeoJson(result));
  return {
    distanceMeters: distance,
    durationSeconds: Number.isFinite(duration) ? duration : null,
    routeCoordinates,
  };
});
