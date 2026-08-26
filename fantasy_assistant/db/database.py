from __future__ import annotations

from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from fantasy_assistant.config import config
from fantasy_assistant.db.models import Base

# timeout=30: si otra conexión tiene la BD bloqueada (ej. el sync de LaLiga
# Fantasy, que ahora dura minutos), SQLite espera hasta 30s en vez de fallar
# al instante con "database is locked" — ver sync_data.sync_once(), que
# además hace commits incrementales para no acaparar el lock tanto tiempo.
connect_args = {"timeout": 30, "check_same_thread": False} if config.database_url.startswith("sqlite") else {}
engine = create_engine(config.database_url, echo=False, future=True, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False, future=True)


def init_db() -> None:
    Base.metadata.create_all(engine)


@contextmanager
def get_session() -> Session:
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
