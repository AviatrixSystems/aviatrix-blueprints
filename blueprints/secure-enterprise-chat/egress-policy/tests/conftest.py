from pathlib import Path
import pytest

FIXTURES = Path(__file__).parent / "fixtures"
CATALOG = Path(__file__).parent.parent / "egress-catalog.yaml"


@pytest.fixture
def fixtures_dir() -> Path:
    return FIXTURES


@pytest.fixture
def catalog_path() -> Path:
    return CATALOG
