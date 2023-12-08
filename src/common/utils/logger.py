# -*- coding: utf-8 -*-
from logging import CRITICAL, DEBUG, ERROR, INFO, WARNING, Logger, _nameToLevel, addLevelName, basicConfig, getLogger
from os import getenv
from typing import Optional, Union

default_level = _nameToLevel.get(getenv("LOG_LEVEL", "INFO").upper(), INFO)
basicConfig(
    format="%(asctime)s [%(name)s] [%(process)d] [%(levelname)s] - %(message)s",
    datefmt="[%Y-%m-%d %H:%M:%S %z]",
    level=default_level,
)

database_default_level = _nameToLevel.get(getenv("DATABASE_LOG_LEVEL", "WARNING").upper(), WARNING)

getLogger("sqlalchemy.orm.mapper.Mapper").setLevel(database_default_level)
getLogger("sqlalchemy.orm.relationships.RelationshipProperty").setLevel(database_default_level)
getLogger("sqlalchemy.orm.strategies.LazyLoader").setLevel(database_default_level)
getLogger("sqlalchemy.pool.impl.QueuePool").setLevel(database_default_level)
getLogger("sqlalchemy.pool.impl.SingletonThreadPool").setLevel(database_default_level)
getLogger("sqlalchemy.engine.Engine").setLevel(database_default_level)

# Edit the default levels of the logging module
addLevelName(CRITICAL, "🚨")
addLevelName(DEBUG, "🐛")
addLevelName(ERROR, "❌")
addLevelName(INFO, "ℹ️ ")
addLevelName(WARNING, "⚠️ ")


def setup_logger(title: str, level: Optional[Union[str, int]] = None) -> Logger:
    """Set up local logger"""
    title = title.upper()
    logger = getLogger(title)
    level = level or default_level

    if isinstance(level, str):
        logger.setLevel(_nameToLevel.get(level.upper(), default_level))
    else:
        logger.setLevel(level)

    return logger


def setup_db_logger(level: Optional[Union[str, int]] = None):
    """Set up local db logger"""
    level = level or database_default_level
    if isinstance(level, str):
        level = _nameToLevel.get(level.upper(), database_default_level)

    getLogger("sqlalchemy.orm.mapper.Mapper").setLevel(level)
    getLogger("sqlalchemy.orm.relationships.RelationshipProperty").setLevel(level)
    getLogger("sqlalchemy.orm.strategies.LazyLoader").setLevel(level)
    getLogger("sqlalchemy.pool.impl.QueuePool").setLevel(level)
    getLogger("sqlalchemy.pool.impl.SingletonThreadPool").setLevel(level)
    getLogger("sqlalchemy.engine.Engine").setLevel(level)
