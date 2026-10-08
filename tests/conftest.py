import pytest

from crlab.engine import Engine

HOG_26 = ["Hog Rider", "Musketeer", "Ice Golem", "Ice Spirit", "Skeletons", "Cannon", "Fireball", "The Log"]
GOLEM = ["Golem", "Night Witch", "Baby Dragon", "Lumberjack", "Mega Minion", "Tornado", "Lightning", "Barbarian Barrel"]


@pytest.fixture(scope="session")
def engine():
    return Engine()
