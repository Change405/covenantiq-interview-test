const express = require("express");
const crypto = require("crypto");

const app = express();
const port = process.env.PORT ? Number(process.env.PORT) : 8080;
const serviceName = process.env.SERVICE_NAME || "service-a";
const appEnv = process.env.APP_ENV || "unknown";

app.use(express.json());

app.use((req, _res, next) => {
  // Simple request id so logs are easier to correlate in smoke tests.
  req.requestId = req.headers["x-request-id"] || crypto.randomUUID();
  next();
});

app.get("/healthz", (req, res) => {
  const payload = {
    ts: new Date().toISOString(),
    level: "info",
    service: serviceName,
    event: "healthz_ok",
    env: appEnv,
    requestId: req.requestId,
  };

  // Always emit to stdout in a deterministic JSON shape.
  console.log(JSON.stringify(payload));
  res.status(200).json({ status: "ok", service: serviceName });
});

app.get("/", (_req, res) => {
  res.status(200).send("ok");
});

app.listen(port, () => {
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      service: serviceName,
      event: "startup",
      env: appEnv,
    })
  );
});

