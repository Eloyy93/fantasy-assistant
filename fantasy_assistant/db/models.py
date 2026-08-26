from __future__ import annotations

from sqlalchemy import Date, ForeignKey, Integer, String, UniqueConstraint
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


class DeviceSubscription(Base):
    """Suscripción de un dispositivo (identificado por su token FCM) a las
    alertas de precio de un jugador concreto, gestionada desde la app."""

    __tablename__ = "device_subscriptions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    fcm_token: Mapped[str] = mapped_column(String, index=True)
    player_id: Mapped[str] = mapped_column(ForeignKey("players.id"), index=True)

    __table_args__ = (UniqueConstraint("fcm_token", "player_id", name="uq_subscription_device_player"),)
