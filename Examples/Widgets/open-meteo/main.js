// Open-Meteo: a scripted widget that fetches a public forecast. No API key.
// Copy this folder into ~/Library/Application Support/OpenDock/Widgets, add a Scripted Widget,
// and pick "Open-Meteo". docs/scripted-widgets.md explains update() and opendock.fetch.

async function update({ settings }) {
  const url =
    "https://api.open-meteo.com/v1/forecast?current=temperature_2m" +
    "&latitude=" + encodeURIComponent(settings.latitude) +
    "&longitude=" + encodeURIComponent(settings.longitude);
  const response = await opendock.fetch(url);
  if (!response.ok) {
    throw new Error("Open-Meteo returned " + response.status);
  }
  const body = await response.json();
  const temperature = body && body.current ? body.current.temperature_2m : null;
  return { temperature: temperature, place: settings.place };
}

function render({ settings, data }) {
  const temperature = data && typeof data.temperature === "number" ? data.temperature : null;
  const place = (data && data.place) || settings.place;
  if (temperature === null) {
    return {
      elements: [
        { type: "icon", symbol: "cloud.sun", color: "secondary" },
        { type: "text", style: "secondary", text: "Waiting for weather" },
      ],
      refresh: 60,
      accessibilityLabel: "Weather is loading",
    };
  }
  const rounded = Math.round(temperature);
  return {
    elements: [
      {
        type: "number",
        value: temperature,
        fractionDigits: 0,
        unit: "°",
        label: place,
      },
    ],
    refresh: settings.refreshMinutes * 60,
    minWidth: 2,
    accessibilityLabel: place + ", " + rounded + " degrees",
  };
}
