from fantasy_assistant.config import config
from fantasy_assistant.datasources.base import FantasyDataSource

SOURCES = ("biwenger", "laligafantasy")


def get_data_source(name: str | None = None) -> FantasyDataSource:
    """Factory: devuelve el adaptador para `name`, o el de FANTASY_SOURCE si
    no se especifica ninguno."""
    name = name or config.fantasy_source
    if name == "biwenger":
        from fantasy_assistant.datasources.biwenger import BiwengerAdapter

        return BiwengerAdapter()
    if name == "laligafantasy":
        from fantasy_assistant.datasources.laligafantasy import LaLigaFantasyAdapter

        return LaLigaFantasyAdapter()
    raise ValueError(f"Fuente de datos desconocida: {name}")
