"""Envío de notificaciones push vía Firebase Cloud Messaging.

Requiere una cuenta de servicio de Firebase (FIREBASE_CREDENTIALS_JSON o
FIREBASE_CREDENTIALS_PATH en .env). Si no está configurada, las funciones de
aquí no hacen nada (con un log de aviso) en vez de romper el resto de la
app — así el backend sigue funcionando sin push mientras no se monte Firebase.
"""
from __future__ import annotations

import json
import logging

from fantasy_assistant.config import config
from fantasy_assistant.modules.alerts import Alert

logger = logging.getLogger(__name__)

_firebase_app = None
_init_attempted = False


def _get_app():
    global _firebase_app, _init_attempted
    if _firebase_app is not None or _init_attempted:
        return _firebase_app
    _init_attempted = True

    if not config.firebase_credentials_json and not config.firebase_credentials_path:
        logger.warning("Firebase no configurado (FIREBASE_CREDENTIALS_JSON/_PATH) — push desactivado")
        return None

    import firebase_admin
    from firebase_admin import credentials

    if config.firebase_credentials_json:
        cred = credentials.Certificate(json.loads(config.firebase_credentials_json))
    else:
        cred = credentials.Certificate(config.firebase_credentials_path)

    _firebase_app = firebase_admin.initialize_app(cred)
    return _firebase_app


def send_alerts(alerts: list[Alert], device_tokens: list[str]) -> list[str]:
    """Envía cada alerta a todos los tokens dados. Devuelve la lista de
    tokens que resultaron inválidos/desregistrados (para limpiarlos de la
    BD)."""
    app = _get_app()
    if app is None or not alerts or not device_tokens:
        return []

    from firebase_admin import messaging

    invalid_tokens: list[str] = []
    for alert in alerts:
        message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title="Fantasy Assistant",
                body=alert.mensaje,
            ),
            data={"player_id": alert.player_id},
            tokens=device_tokens,
        )
        response = messaging.send_each_for_multicast(message, app=app)
        for token, result in zip(device_tokens, response.responses):
            if not result.success and result.exception is not None:
                code = getattr(result.exception, "code", "")
                if code in ("NOT_FOUND", "UNREGISTERED", "INVALID_ARGUMENT"):
                    invalid_tokens.append(token)

    return invalid_tokens
