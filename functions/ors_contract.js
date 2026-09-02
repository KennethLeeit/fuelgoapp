class ContractError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function finiteCoordinate(value, min, max, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    throw new ContractError("invalid-argument", `${label} is invalid.`);
  }
  return number;
}

function malaysiaCoordinate(data) {
  const latitude = finiteCoordinate(data?.latitude, 0.8, 7.5, "Latitude");
  const longitude = finiteCoordinate(data?.longitude, 99.5, 119.5, "Longitude");
  return {latitude, longitude};
}

function malaysiaQuery(data) {
  const query = String(data?.query || "").trim();
  if (query.length < 2 || query.length > 120) {
    throw new ContractError(
        "invalid-argument",
        "Enter between 2 and 120 characters.",
    );
  }
  return query;
}

function isMalaysian(properties = {}) {
  const code = String(
      properties.country_a || properties.country_code || "",
  ).toUpperCase();
  return code === "MY" || code === "MYS";
}

function placeFromFeature(feature) {
  const coordinates = feature?.geometry?.coordinates;
  const properties = feature?.properties || {};
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  if (!isMalaysian(properties)) return null;
  const longitude = Number(coordinates[0]);
  const latitude = Number(coordinates[1]);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const address = String(properties.label || properties.name || "").trim();
  const name = String(properties.name || address.split(",")[0] || "").trim();
  if (!name || !address) return null;
  return {name, address, latitude, longitude};
}

function pointsAreTooClose(from, to) {
  return Math.abs(from.latitude - to.latitude) < 0.00045 &&
    Math.abs(from.longitude - to.longitude) < 0.00045;
}

module.exports = {
  ContractError,
  malaysiaCoordinate,
  malaysiaQuery,
  placeFromFeature,
  pointsAreTooClose,
};
