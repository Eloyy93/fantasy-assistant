"""añade estado/estado_info a players (lesión, duda, sanción)

Revision ID: a1b2c3d4e5f6
Revises: 7103b1c86c47
Create Date: 2026-09-13 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '7103b1c86c47'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('players', sa.Column('estado', sa.String(), nullable=False, server_default='ok'))
    op.add_column('players', sa.Column('estado_info', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('players', 'estado_info')
    op.drop_column('players', 'estado')
