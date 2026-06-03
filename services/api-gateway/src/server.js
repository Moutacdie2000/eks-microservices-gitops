import express from "express";
import morgan from "morgan";
import { createProxyMiddleware } from "http-proxy-middleware";
import client from "prom-client";

const PORT = process.env.PORT || 8080;
const ORDERS_URL = process.env.ORDERS_URL || "http://orders:8000";
const PAYMENTS_URL = process.env.PAYMENTS_URL || "http://payments:8000";

const app = express();
app.use(morgan("combined"));

// --- Métriques Prometheus ---
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Durée des requêtes HTTP en secondes.",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5],
});
register.registerMetric(httpRequestDuration);

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on("finish", () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

// --- Sondes de santé ---
// /health : liveness, le process répond.
app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok", service: "api-gateway" });
});

// /ready : readiness, prêt à recevoir du trafic.
app.get("/ready", (_req, res) => {
  res.status(200).json({ status: "ready", service: "api-gateway" });
});

app.get("/metrics", async (_req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// --- Routage vers les microservices en aval ---
app.use(
  "/api/orders",
  createProxyMiddleware({
    target: ORDERS_URL,
    changeOrigin: true,
    pathRewrite: { "^/api/orders": "/orders" },
  })
);

app.use(
  "/api/payments",
  createProxyMiddleware({
    target: PAYMENTS_URL,
    changeOrigin: true,
    pathRewrite: { "^/api/payments": "/payments" },
  })
);

app.get("/", (_req, res) => {
  res.json({
    service: "api-gateway",
    routes: ["/api/orders", "/api/payments", "/health", "/ready", "/metrics"],
  });
});

const server = app.listen(PORT, () => {
  console.log(`api-gateway à l'écoute sur le port ${PORT}`);
});

// Arrêt gracieux pour laisser le temps aux connexions de se terminer (rolling update).
process.on("SIGTERM", () => {
  console.log("SIGTERM reçu, arrêt gracieux...");
  server.close(() => process.exit(0));
});
