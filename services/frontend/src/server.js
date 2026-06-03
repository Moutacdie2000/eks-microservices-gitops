import express from "express";
import morgan from "morgan";

const PORT = process.env.PORT || 8080;
// URL publique de l'api-gateway, injectée dans la page pour les appels côté client.
const API_BASE_URL = process.env.API_BASE_URL || "/api";

const app = express();
app.use(morgan("combined"));

app.get("/health", (_req, res) => {
  res.status(200).json({ status: "ok", service: "frontend" });
});

app.get("/ready", (_req, res) => {
  res.status(200).json({ status: "ready", service: "frontend" });
});

app.get("/", (_req, res) => {
  res.set("Content-Type", "text/html; charset=utf-8");
  res.send(`<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Shop Platform — Démo GitOps</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 2rem auto; max-width: 720px; line-height: 1.5; }
      button { padding: 0.5rem 1rem; cursor: pointer; }
      pre { background: #f4f4f4; padding: 1rem; border-radius: 6px; overflow-x: auto; }
    </style>
  </head>
  <body>
    <h1>Shop Platform</h1>
    <p>Frontend de démonstration déployé sur EKS via ArgoCD (GitOps).</p>
    <button id="order-btn">Créer une commande</button>
    <button id="pay-btn">Lancer un paiement</button>
    <pre id="output">Résultat…</pre>
    <script>
      const API = ${JSON.stringify(API_BASE_URL)};
      const out = document.getElementById("output");
      async function call(path, body) {
        try {
          const res = await fetch(API + path, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
          });
          out.textContent = JSON.stringify(await res.json(), null, 2);
        } catch (e) {
          out.textContent = "Erreur : " + e.message;
        }
      }
      document.getElementById("order-btn").onclick = () =>
        call("/orders", { items: [{ sku: "DEMO-1", qty: 2 }] });
      document.getElementById("pay-btn").onclick = () =>
        call("/payments", { orderId: "demo-order", amount: 4990, currency: "EUR" });
    </script>
  </body>
</html>`);
});

const server = app.listen(PORT, () => {
  console.log(`frontend à l'écoute sur le port ${PORT}`);
});

process.on("SIGTERM", () => {
  console.log("SIGTERM reçu, arrêt gracieux...");
  server.close(() => process.exit(0));
});
