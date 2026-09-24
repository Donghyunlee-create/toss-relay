"""Toss Open API read-only relay. Allowlists GET paths; never forwards mutating methods."""
from __future__ import annotations

import os
import re
import secrets
import threading
import time
from collections import defaultdict, deque

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

TOSS_BASE = os.environ.get("TOSS_BASE_URL", "https://openapi.tossinvest.com").rstrip("/")
TOSS_TOKEN_URL = os.environ.get("TOSS_TOKEN_URL", f"{TOSS_BASE}/oauth2/token")
CLIENT_ID = os.environ.get("TOSS_CLIENT_ID", "")
CLIENT_SECRET = os.environ.get("TOSS_CLIENT_SECRET", "")
ACCOUNT_SEQ = os.environ.get("TOSS_ACCOUNT_SEQ", "")
RELAY_TOKEN = os.environ.get("RELAY_TOKEN", "")
RATE_LIMIT = int(os.environ.get("RATE_LIMIT_PER_MINUTE", "60"))

# Exact prefixes / patterns for read-only GETs only (OpenAPI 1.2.x).
_ALLOWED = [
    re.compile(p)
    for p in [
        r"^/api/v1/orderbook$",
        r"^/api/v1/prices$",
        r"^/api/v1/trades$",
        r"^/api/v1/price-limits$",
        r"^/api/v1/candles$",
        r"^/api/v1/stocks$",
        r"^/api/v1/stocks/all$",
        r"^/api/v1/stocks/[^/]+/warnings$",
        r"^/api/v1/stocks/[^/]+/investor-trading$",
        r"^/api/v1/stocks/[^/]+/program-trades$",
        r"^/api/v1/stocks/[^/]+/short-selling$",
        r"^/api/v1/stocks/[^/]+/credit-trades$",
        r"^/api/v1/stocks/[^/]+/securities-lending$",
        r"^/api/v1/exchange-rate$",
        r"^/api/v1/market-calendar/KR$",
        r"^/api/v1/market-calendar/US$",
        r"^/api/v1/rankings$",
        r"^/api/v1/market-indicators/prices$",
        r"^/api/v1/market-indicators/[^/]+/candles$",
        r"^/api/v1/market-indicators/[^/]+/investor-trading$",
        r"^/api/v1/accounts$",
        r"^/api/v1/holdings$",
        r"^/api/v1/orders$",
        r"^/api/v1/orders/[^/]+$",
        r"^/api/v1/conditional-orders$",
        r"^/api/v1/conditional-orders/[^/]+$",
        r"^/api/v1/buying-power$",
        r"^/api/v1/sellable-quantity$",
        r"^/api/v1/commissions$",
    ]
]

_PASS_HEADERS = ("x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset", "retry-after")

app = FastAPI(title="Toss read-only relay", docs_url=None, redoc_url=None)
_token_lock = threading.Lock()
_cached_token: str | None = None
_token_expires_at = 0.0
_rate: dict[str, deque[float]] = defaultdict(deque)
_rate_lock = threading.Lock()
_http: httpx.Client | None = None


def _client() -> httpx.Client:
    global _http
    if _http is None:
        _http = httpx.Client(timeout=30.0)
    return _http


def _allowed(path: str) -> bool:
    return any(r.match(path) for r in _ALLOWED)


def _auth_ok(request: Request) -> bool:
    if not RELAY_TOKEN:
        return False
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return False
    return secrets.compare_digest(auth[7:].strip(), RELAY_TOKEN)


def _rate_ok(key: str) -> bool:
    now = time.time()
    with _rate_lock:
        q = _rate[key]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= RATE_LIMIT:
            return False
        q.append(now)
        return True


def _toss_token(force: bool = False) -> str:
    global _cached_token, _token_expires_at
    with _token_lock:
        if not force and _cached_token and time.time() < _token_expires_at - 60:
            return _cached_token
        r = _client().post(
            TOSS_TOKEN_URL,
            data={"grant_type": "client_credentials", "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET},
        )
        r.raise_for_status()
        data = r.json()
        _cached_token = data["access_token"]
        _token_expires_at = time.time() + float(data.get("expires_in", 3600))
        return _cached_token


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True}


@app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
async def relay(full_path: str, request: Request) -> Response:
    path = "/" + full_path.lstrip("/")
    if request.method != "GET":
        return JSONResponse({"error": "method_not_allowed"}, status_code=405)
    if not _allowed(path):
        return JSONResponse({"error": "not_found"}, status_code=404)
    if not _auth_ok(request):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    client_key = request.client.host if request.client else "unknown"
    if not _rate_ok(client_key):
        return JSONResponse({"error": "rate_limited"}, status_code=429)

    account = request.headers.get("x-tossinvest-account") or ACCOUNT_SEQ

    def _get(force: bool = False) -> httpx.Response:
        headers = {"Authorization": f"Bearer {_toss_token(force)}", "Accept": "application/json"}
        if account:
            headers["X-Tossinvest-Account"] = account
        # Only GET is ever sent upstream (besides the OAuth token request).
        return _client().get(f"{TOSS_BASE}{path}", params=dict(request.query_params), headers=headers)

    upstream = _get()
    if upstream.status_code == 401:  # token invalidated (Toss keeps one live token per client)
        upstream = _get(force=True)
    out_headers = {h: upstream.headers[h] for h in _PASS_HEADERS if h in upstream.headers}
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        headers=out_headers,
        media_type=upstream.headers.get("content-type", "application/json"),
    )
