"""Prove mutating paths/methods never contact Toss (httpx Client is mocked)."""
from __future__ import annotations

import os

import httpx
import pytest
from fastapi.testclient import TestClient

# Set env before importing app
os.environ["RELAY_TOKEN"] = "test-relay-token-aaaaaaaaaaaaaaaaaaaaaaaa"
os.environ["TOSS_CLIENT_ID"] = "cid"
os.environ["TOSS_CLIENT_SECRET"] = "csec"
os.environ["TOSS_ACCOUNT_SEQ"] = "1"
os.environ["RATE_LIMIT_PER_MINUTE"] = "1000"

import app as relay_app  # noqa: E402


class ExplodingClient:
    """Any network call fails the test."""

    def get(self, *a, **k):
        raise AssertionError(f"unexpected GET to Toss: {a} {k}")

    def post(self, *a, **k):
        raise AssertionError(f"unexpected POST to Toss: {a} {k}")


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(relay_app, "_http", ExplodingClient())
    monkeypatch.setattr(relay_app, "_cached_token", None)
    monkeypatch.setattr(relay_app, "_token_expires_at", 0.0)
    return TestClient(relay_app.app)


MUTATING = [
    ("POST", "/api/v1/orders"),
    ("POST", "/api/v1/orders/abc/modify"),
    ("POST", "/api/v1/orders/abc/cancel"),
    ("POST", "/api/v1/conditional-orders"),
    ("DELETE", "/api/v1/conditional-orders/abc"),
    ("POST", "/api/v1/conditional-orders/abc/modify"),
    ("PUT", "/api/v1/orders"),
    ("PATCH", "/api/v1/holdings"),
]


@pytest.mark.parametrize("method,path", MUTATING)
def test_mutating_blocked_without_toss(client, method, path):
    r = client.request(method, path, headers={"Authorization": "Bearer " + os.environ["RELAY_TOKEN"]})
    assert r.status_code in (404, 405), (method, path, r.status_code, r.text)


def test_unknown_get_is_404_without_toss(client):
    r = client.get("/api/v1/orders/abc/modify", headers={"Authorization": "Bearer " + os.environ["RELAY_TOKEN"]})
    assert r.status_code == 404


def test_get_orders_without_auth_is_401_without_toss(client):
    r = client.get("/api/v1/orders")
    assert r.status_code == 401


def test_healthz(client):
    assert client.get("/healthz").json() == {"ok": True}
