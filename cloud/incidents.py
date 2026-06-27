#!/usr/bin/env python3
"""Reliability incident logging for node health and scheduler trust."""

import json
import logging
from datetime import datetime, timezone
from typing import Any

from cloud import db

logger = logging.getLogger("cloud.incidents")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log(
    node_id: str,
    incident_type: str,
    *,
    severity: str = "info",
    target_name: str = "",
    measurement_id: int | None = None,
    detail: dict[str, Any] | None = None,
) -> None:
    """Record an operational incident without letting logging failure affect hot paths."""
    if not node_id:
        return
    try:
        db.execute(
            """INSERT INTO reliability_incidents
                   (node_id, incident_type, severity, target_name, measurement_id,
                    detail, occurred_at)
               VALUES (%s,%s,%s,%s,%s,%s,%s)""",
            (
                node_id,
                incident_type[:80],
                severity[:24],
                target_name[:160],
                measurement_id,
                json.dumps(detail or {}),
                _now(),
            ),
        )
    except Exception as exc:
        logger.warning("Could not record reliability incident for %s: %s", node_id, exc)
