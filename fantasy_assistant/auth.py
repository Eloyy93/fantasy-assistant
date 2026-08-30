"""Verificación de sesión (Google Sign-In vía Firebase Auth).

Iniciar sesión es OPCIONAL en toda la API: cada endpoint de "Mi
plantilla" sigue aceptando el `device_id` de siempre para uso anónimo.
Cuando la app manda además `Authorization: Bearer <id_token>`, ese token
se verifica contra Firebase y sus datos pasan a ser los que identifican
al usuario (ver `resolve_owner_id`).
"""
from __future__ import annotations

import logging

from sqlalchemy.orm import Session

from fantasy_assistant.db.models import User
from fantasy_assistant.notifications.fcm import get_firebase_app

logger = logging.getLogger(__name__)


class TokenInvalido(Exception):
    pass


def verificar_token(id_token: str) -> dict:
    """Verifica un ID token de Firebase (emitido tras el login con Google
    en la app) y devuelve sus claims (uid, email, name, picture...).
    Lanza TokenInvalido si no se puede verificar."""
    app = get_firebase_app()
    if app is None:
        raise TokenInvalido("Firebase no está configurado en el servidor")

    from firebase_admin import auth as firebase_auth

    try:
        return firebase_auth.verify_id_token(id_token, app=app)
    except Exception as e:
        raise TokenInvalido(str(e)) from e


def resolve_owner_id(db: Session, device_id: str | None, authorization: str | None) -> str:
    """Identidad efectiva para las tablas de "Mi plantilla": si hay un
    token válido en la cabecera Authorization, `user:<uid>` (y de paso se
    actualiza/crea la fila de User); si no, `device:<device_id>` — el
    comportamiento de siempre, sin sesión iniciada."""
    if authorization and authorization.lower().startswith("bearer "):
        id_token = authorization[7:].strip()
        try:
            claims = verificar_token(id_token)
        except TokenInvalido as e:
            logger.warning("Token de sesión inválido, se usa device_id de respaldo: %s", e)
        else:
            uid = claims["uid"]
            usuario = db.get(User, uid)
            if usuario is None:
                db.add(
                    User(
                        id=uid,
                        email=claims.get("email"),
                        nombre=claims.get("name"),
                        foto_url=claims.get("picture"),
                    )
                )
            else:
                usuario.email = claims.get("email") or usuario.email
                usuario.nombre = claims.get("name") or usuario.nombre
                usuario.foto_url = claims.get("picture") or usuario.foto_url
            return f"user:{uid}"

    if not device_id:
        raise ValueError("Falta device_id (y no hay sesión iniciada)")
    return f"device:{device_id}"
