#!/usr/bin/env python3
"""
Focused contract tests for activation-code node registration.

Run with:  python3 -m unittest tests.test_activation_contract
"""

import json
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import cloud.server as server


def _iso(days: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()


class ActivationRegistrationContractTest(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()

    def _post_register(self, body):
        return self.client.post("/api/v1/nodes/register", json=body)

    @patch("cloud.server.registry.register_node")
    @patch("cloud.server.db.query_one", return_value=None)
    def test_unknown_activation_code_rejected_before_registration(self, query_one, register_node):
        resp = self._post_register({"activation_code": "BS-2026-MISSING1"})

        self.assertEqual(resp.status_code, 404)
        self.assertIn("activation code not found", resp.get_json()["error"])
        register_node.assert_not_called()

    @patch("cloud.server.registry.register_node")
    def test_used_activation_code_rejected_before_registration(self, register_node):
        with patch("cloud.server.db.query_one", return_value={"used_at": _iso(-1)}):
            resp = self._post_register({"activation_code": "BS-2026-USED0001"})

        self.assertEqual(resp.status_code, 409)
        self.assertEqual(resp.get_json()["error"], "activation code already used")
        register_node.assert_not_called()

    @patch("cloud.server.registry.register_node")
    def test_expired_activation_code_rejected_before_registration(self, register_node):
        with patch("cloud.server.db.query_one", return_value={
            "used_at": "",
            "expires_at": _iso(-1),
        }):
            resp = self._post_register({"activation_code": "BS-2026-EXPIRED1"})

        self.assertEqual(resp.status_code, 410)
        self.assertEqual(resp.get_json()["error"], "activation code expired")
        register_node.assert_not_called()

    def test_valid_activation_code_backfills_and_links_member(self):
        code = "BS-2026-VALID001"
        code_row = {
            "code": code,
            "user_id": "u_member",
            "used_at": "",
            "expires_at": _iso(30),
            "latitude": 41.0123,
            "longitude": -73.9876,
            "observatory_name": "Backyard Pier",
            "telescope_model": "ZWO Seestar S50",
            "telescope_specs": json.dumps({
                "aperture_mm": 50,
                "focal_length_mm": 250,
                "filter_set": ["CV"],
            }),
            "portable": 1,
        }
        executed = []

        def query_one(sql, params=()):
            if "FROM activation_codes" in sql:
                return code_row
            if "FROM node_members" in sql:
                return None
            self.fail(f"Unexpected query: {sql}")

        def execute(sql, params=()):
            executed.append((sql, params))

        with patch("cloud.server.db.query_one", side_effect=query_one), \
             patch("cloud.server.db.execute", side_effect=execute), \
             patch("cloud.server.registry.register_node",
                   return_value={"node_id": "node_abc", "api_key": "secret"}) as register_node:
            resp = self._post_register({
                "activation_code": code,
                "latitude": 0,
                "longitude": 0,
            })

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get_json()["node_id"], "node_abc")

        payload = register_node.call_args.args[0]
        self.assertEqual(payload["latitude"], code_row["latitude"])
        self.assertEqual(payload["longitude"], code_row["longitude"])
        self.assertEqual(payload["owner_name"], "Backyard Pier")
        self.assertEqual(payload["telescope_model"], "ZWO Seestar S50")
        self.assertEqual(payload["aperture_mm"], 50)
        self.assertEqual(payload["focal_length_mm"], 250)
        self.assertEqual(payload["filter_set"], '["CV"]')
        self.assertTrue(payload["portable"])

        joined_sql = "\n".join(sql for sql, _ in executed)
        self.assertIn("UPDATE activation_codes SET used_at", joined_sql)
        self.assertIn("INSERT INTO node_members", joined_sql)


if __name__ == "__main__":
    unittest.main()
