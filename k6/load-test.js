// Test de charge k6 destiné à démontrer le HorizontalPodAutoscaler (HPA).
//
// Le scénario monte progressivement en charge pour faire grimper l'utilisation
// CPU des pods api-gateway/orders/payments au-dessus de la cible HPA (60 %),
// ce qui doit déclencher un scale-up, puis redescend pour observer le scale-down.
//
// Usage :
//   BASE_URL=https://api.shop.example.com k6 run k6/load-test.js
//
// Observation en parallèle :
//   kubectl get hpa -A -w
//   kubectl get pods -n orders -w

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

const errorRate = new Rate("errors");
const orderLatency = new Trend("order_latency", true);

export const options = {
  scenarios: {
    // Montée en charge en escalier pour forcer le scale-up du HPA.
    ramping_load: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "1m", target: 50 },   // montée
        { duration: "2m", target: 150 },  // pic — doit déclencher le scale-up
        { duration: "3m", target: 150 },  // palier — HPA stabilise les répliques
        { duration: "2m", target: 0 },    // descente — observer le scale-down
      ],
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<800"], // 95e percentile sous 800 ms
    errors: ["rate<0.02"],            // moins de 2 % d'erreurs
  },
};

export default function () {
  // 1) Création d'une commande via l'api-gateway → service orders.
  const orderPayload = JSON.stringify({
    items: [
      { sku: "SKU-1001", qty: 2 },
      { sku: "SKU-2002", qty: 1 },
    ],
  });
  const orderRes = http.post(`${BASE_URL}/api/orders`, orderPayload, {
    headers: { "Content-Type": "application/json" },
  });
  orderLatency.add(orderRes.timings.duration);
  const orderOk = check(orderRes, {
    "order status 201": (r) => r.status === 201,
  });
  errorRate.add(!orderOk);

  // 2) Paiement de la commande via l'api-gateway → service payments.
  const payPayload = JSON.stringify({
    orderId: "load-test",
    amount: 4990,
    currency: "EUR",
  });
  const payRes = http.post(`${BASE_URL}/api/payments`, payPayload, {
    headers: { "Content-Type": "application/json" },
  });
  const payOk = check(payRes, {
    "payment status 201": (r) => r.status === 201,
  });
  errorRate.add(!payOk);

  sleep(0.5);
}
