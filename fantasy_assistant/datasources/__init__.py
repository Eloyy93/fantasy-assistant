from fantasy_assistant.config import config
from fantasy_assistant.datasources.base import FantasyDataSource


def get_data_source() -> FantasyDataSource:
    """Factory: devuelve el adaptador activo según FANTASY_SOURCE."""
    if config.fantasy_source == "biwenger":
        from fantasy_assistant.datasources.biwenger import BiwengerAdapter

        return BiwengerAdapter()
    if config.fantasy_source == "laligafantasy":
        from fantasy_assistant.datasources.laligafantasy import LaLigaFantasyAdapter

        return LaLigaFantasyAdapter()
    raise ValueError(f"Fuente de datos desconocida: {config.fantasy_source}")
