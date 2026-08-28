from __future__ import annotations

from sqlalchemy import Boolean, Date, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class PlayerRecord(Base):
    """Un jugador. `id` es el id compuesto `{source}:{player_id}` para no
    mezclar jugadores de fuentes distintas (los ids no son compatibles entre
    Biwenger y LaLiga Fantasy)."""

    __tablename__ = "players"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    source: Mapped[str] = mapped_column(String, index=True)
    external_id: Mapped[str] = mapped_column(String, index=True)
    nombre: Mapped[str] = mapped_column(String)
    equipo: Mapped[str] = mapped_column(String)
    posicion: Mapped[str] = mapped_column(String)
    precio: Mapped[int] = mapped_column(Integer, default=0)

    price_history: Mapped[list["PriceHistory"]] = relationship(back_populates="player", cascade="all, delete-orphan")
    points_history: Mapped[list["PointsHistory"]] = relationship(back_populates="player", cascade="all, delete-orphan")

    __table_args__ = (UniqueConstraint("source", "external_id", name="uq_player_source_external_id"),)

    @property
    def foto_url(self) -> str:
        """URL de la foto del jugador, calculada a partir de su id — no
        hace falta guardarla en BD. Ambas fuentes usan un CDN con el id
        externo directamente en la ruta:
        - Biwenger: cdn.biwenger.com/i/p/{id}.png (verificado con curl).
        - LaLiga Fantasy: media.futbolfantasy.com/uploads/images/jugadores/ficha/{id}.png.
        No todos los jugadores tienen foto (algunas rutas dan 404) — el
        cliente debe manejar el fallo de carga con un icono/inicial, no
        asumir que la URL siempre resuelve."""
        if self.source == "biwenger":
            return f"https://cdn.biwenger.com/i/p/{self.external_id}.png"
        if self.source == "laligafantasy":
            return f"https://media.futbolfantasy.com/uploads/images/jugadores/ficha/{self.external_id}.png"
        return ""


class PriceHistory(Base):
    __tablename__ = "price_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    source: Mapped[str] = mapped_column(String, index=True)
    fecha: Mapped[str] = mapped_column(Date)
    precio: Mapped[int] = mapped_column(Integer)

    player: Mapped["PlayerRecord"] = relationship(back_populates="price_history")

    __table_args__ = (UniqueConstraint("player_id", "fecha", name="uq_price_player_fecha"),)


class PointsHistory(Base):
    __tablename__ = "points_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    source: Mapped[str] = mapped_column(String, index=True)
    jornada: Mapped[int] = mapped_column(Integer)
    puntos: Mapped[int] = mapped_column(Integer)

    player: Mapped["PlayerRecord"] = relationship(back_populates="points_history")

    __table_args__ = (UniqueConstraint("player_id", "jornada", name="uq_points_player_jornada"),)


class DeviceRegistration(Base):
    """Token FCM de un dispositivo Android para poder enviarle notificaciones
    push. Registrado por la app desde POST /devices."""

    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fcm_token: Mapped[str] = mapped_column(String, unique=True, index=True)
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=True)
    # Opt-in aparte de las suscripciones por jugador: un chollo es, por
    # definición, un jugador que el usuario todavía no conoce/sigue, así
    # que no tiene sentido pedirle que se suscriba uno a uno.
    notificar_chollos: Mapped[bool] = mapped_column(Boolean, default=False, server_default="0")


class DeviceSubscription(Base):
    """Suscripción de un dispositivo (identificado por su token FCM) a las
    alertas de precio de un jugador concreto, gestionada desde la app."""

    __tablename__ = "device_subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fcm_token: Mapped[str] = mapped_column(String, index=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)

    __table_args__ = (UniqueConstraint("fcm_token", "player_id", name="uq_subscription_device_player"),)


class TeamPlayer(Base):
    """Jugador que el usuario ha colocado en "Mi plantilla" desde la app.
    Identificado por un device_id local generado por la app (no el token
    FCM), para que gestionar la plantilla no dependa de tener las
    notificaciones activadas.

    `slot` es la posición exacta dentro de la formación elegida (ej.
    "DEF2"), al estilo Futbin/Ultimate Team — null si el jugador está en la
    plantilla pero no colocado en el campo (añadido antes de esta función,
    o quitado de su hueco al cambiar de formación).

    `source` es un duplicado de `PlayerRecord.source` (evita un join solo
    para saber la fuente) y, sobre todo, scoping: los nombres de slot
    ("DEF2", "MED1"...) son los mismos en Biwenger y LaLiga Fantasy, así
    que sin esta columna en el UNIQUE/las consultas, colocar un jugador en
    "MED1" de una fuente detectaba como "ocupante" al jugador de la OTRA
    fuente en ese mismo slot y lo mandaba al banquillo — visto en
    producción como "el jugador desaparece" al usar ambas fuentes."""

    __tablename__ = "team_players"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String, index=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)
    source: Mapped[str] = mapped_column(String, index=True)
    slot: Mapped[str | None] = mapped_column(String, nullable=True)

    __table_args__ = (
        UniqueConstraint("device_id", "player_id", name="uq_team_device_player"),
        # SQLite trata cada NULL como distinto en un UNIQUE, así que varios
        # jugadores sin colocar (slot=NULL) del mismo device_id conviven sin
        # problema — el UNIQUE solo se aplica de verdad entre huecos reales.
        # Incluye `source` para que el mismo nombre de slot en fuentes
        # distintas no choque (ver docstring de la clase).
        UniqueConstraint("device_id", "slot", "source", name="uq_team_device_slot_source"),
    )


class TeamFormation(Base):
    """Formación elegida por el usuario para "Mi plantilla", por fuente
    (Biwenger y LaLiga Fantasy pueden tener formaciones distintas)."""

    __tablename__ = "team_formations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    device_id: Mapped[str] = mapped_column(String, index=True)
    source: Mapped[str] = mapped_column(String)
    formacion: Mapped[str] = mapped_column(String)

    __table_args__ = (UniqueConstraint("device_id", "source", name="uq_formation_device_source"),)


class BargainState(Base):
    """Último estado conocido de "es chollo" de cada jugador, para poder
    notificar solo cuando un jugador *se convierte* en chollo (transición
    False -> True) en vez de cada vez que se sincroniza mientras lo siga
    siendo — si no, la misma alerta se repetiría cada 3h sin aportar nada
    nuevo."""

    __tablename__ = "bargain_state"

    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), primary_key=True)
    es_chollo: Mapped[bool] = mapped_column(Boolean, default=False)
