const test = require("node:test");
const assert = require("node:assert/strict");
const {
  ContractError,
  malaysiaCoordinate,
  malaysiaQuery,
  placeFromFeature,
  pointsAreTooClose,
  routeCoordinatesFromGeoJson,
} = require("../ors_contract");

test("search query is trimmed and bounded", () => {
  assert.equal(malaysiaQuery({query: "  KLCC  "}), "KLCC");
  assert.throws(() => malaysiaQuery({query: "K"}), ContractError);
  assert.throws(() => malaysiaQuery({query: "x".repeat(121)}), ContractError);
});

test("route geometry is validated and converted to latitude/longitude", () => {
  const points = routeCoordinatesFromGeoJson({
    features: [{
      geometry: {
        coordinates: [[101.6869, 3.139], [101.7123, 3.1579]],
      },
    }],
  });
  assert.deepEqual(points, [
    {latitude: 3.139, longitude: 101.6869},
    {latitude: 3.1579, longitude: 101.7123},
  ]);
  assert.throws(() => routeCoordinatesFromGeoJson({features: []}), ContractError);
});

test("coordinates must stay within the Malaysia service boundary", () => {
  assert.deepEqual(
      malaysiaCoordinate({latitude: 3.139, longitude: 101.6869}),
      {latitude: 3.139, longitude: 101.6869},
  );
  assert.throws(
      () => malaysiaCoordinate({latitude: -6.2, longitude: 106.8}),
      ContractError,
  );
  assert.throws(
      () => malaysiaCoordinate({latitude: 3.1, longitude: "not-a-number"}),
      ContractError,
  );
});

test("only Malaysian geocoder features are converted", () => {
  const malaysia = placeFromFeature({
    geometry: {coordinates: [101.7123, 3.1579]},
    properties: {
      country_a: "MYS",
      name: "KLCC",
      label: "KLCC, Kuala Lumpur, Malaysia",
    },
  });
  const foreign = placeFromFeature({
    geometry: {coordinates: [103.8198, 1.3521]},
    properties: {country_a: "SGP", name: "Singapore"},
  });

  assert.equal(malaysia.name, "KLCC");
  assert.equal(malaysia.latitude, 3.1579);
  assert.equal(foreign, null);
});

test("same-place protection rejects effectively identical points", () => {
  assert.equal(
      pointsAreTooClose(
          {latitude: 3.1, longitude: 101.7},
          {latitude: 3.1001, longitude: 101.7001},
      ),
      true,
  );
  assert.equal(
      pointsAreTooClose(
          {latitude: 3.1, longitude: 101.7},
          {latitude: 3.2, longitude: 101.8},
      ),
      false,
  );
});
