"""Microservice orders — gestion minimale des commandes (FastAPI)."""
from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from pydantic import BaseModel, Field

SERVICE_NAME = "orders"
PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments:8000")

app = FastAPI(title="Orders Service", version="1.0.0")

orders_created_total = Counter(
    "orders_created_total", "Nombre total de commandes créées."
)


class OrderItem(BaseModel):
    sku: str = Field(..., min_length=1, description="Référence produit.")
    qty: int = Field(..., gt=0, description="Quantité commandée.")


class OrderRequest(BaseModel):
    items: list[OrderItem] = Field(..., min_length=1)


class OrderResponse(BaseModel):
    order_id: str
    status: str
    item_count: int
    created_at: str


@app.get("/health")
def health() -> dict[str, str]:
    """Liveness : le process répond."""
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/ready")
def ready() -> dict[str, str]:
    """Readiness : prêt à recevoir du trafic."""
    return {"status": "ready", "service": SERVICE_NAME}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/orders", response_model=OrderResponse, status_code=201)
def create_order(payload: OrderRequest) -> OrderResponse:
    """Crée une commande et renvoie son identifiant.

    Dans une vraie plateforme, cette route persisterait la commande puis
    émettrait un événement vers le service payments. Ici on simule la création.
    """
    order_id = f"ord_{uuid.uuid4().hex[:12]}"
    item_count = sum(item.qty for item in payload.items)
    orders_created_total.inc()
    return OrderResponse(
        order_id=order_id,
        status="created",
        item_count=item_count,
        created_at=datetime.now(timezone.utc).isoformat(),
    )


@app.get("/orders/{order_id}", response_model=OrderResponse)
def get_order(order_id: str) -> OrderResponse:
    """Récupère une commande (réponse simulée pour la démo)."""
    return OrderResponse(
        order_id=order_id,
        status="created",
        item_count=1,
        created_at=datetime.now(timezone.utc).isoformat(),
    )
