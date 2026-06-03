"""Microservice payments, autorisation minimale de paiements (FastAPI)."""
from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from pydantic import BaseModel, Field

SERVICE_NAME = "payments"
# En production, le secret du PSP serait lu via IRSA depuis AWS Secrets Manager.
PSP_SECRET_ARN = os.getenv("PSP_SECRET_ARN", "")

app = FastAPI(title="Payments Service", version="1.0.0")

payments_processed_total = Counter(
    "payments_processed_total",
    "Nombre total de paiements traités.",
    ["status"],
)


class PaymentRequest(BaseModel):
    order_id: str = Field(..., alias="orderId", min_length=1)
    amount: int = Field(..., gt=0, description="Montant en centimes.")
    currency: str = Field(default="EUR", min_length=3, max_length=3)

    model_config = {"populate_by_name": True}


class PaymentResponse(BaseModel):
    payment_id: str
    order_id: str
    status: str
    amount: int
    currency: str
    processed_at: str


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


@app.post("/payments", response_model=PaymentResponse, status_code=201)
def process_payment(payload: PaymentRequest) -> PaymentResponse:
    """Autorise un paiement pour une commande donnée.

    Logique simulée : tout montant strictement positif est « capturé ».
    Une implémentation réelle appellerait un PSP (Stripe, Adyen…) avec un secret
    obtenu via IRSA, puis émettrait un événement de confirmation.
    """
    payment_id = f"pay_{uuid.uuid4().hex[:12]}"
    payments_processed_total.labels(status="captured").inc()
    return PaymentResponse(
        payment_id=payment_id,
        order_id=payload.order_id,
        status="captured",
        amount=payload.amount,
        currency=payload.currency,
        processed_at=datetime.now(timezone.utc).isoformat(),
    )
