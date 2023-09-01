from random import uniform
from typing import Dict, List, Literal, Union
from fastapi import APIRouter, BackgroundTasks, status
from fastapi.responses import JSONResponse

from ..models import (
    CustomConfigModel,
    CustomConfigDataModel,
    CustomConfigNameModel,
    ErrorMessage,
)
from ..dependencies import CORE_CONFIG, DB, send_to_instances

router = APIRouter(prefix="/custom_configs", tags=["custom_configs"])


@router.get(
    "",
    response_model=List[CustomConfigDataModel],
    summary="Get all custom configs",
    response_description="List of custom configs",
)
async def get_custom_configs():
    """
    Get all custom configs
    """
    return DB.get_custom_configs()


@router.put(
    "",
    response_model=Dict[Literal["message"], str],
    summary="Update one or more custom configs",
    response_description="Message",
    responses={
        status.HTTP_403_FORBIDDEN: {
            "description": "Can't update a custom config created by the core or the autoconf if the method isn't one of them",
            "model": ErrorMessage,
        },
        status.HTTP_503_SERVICE_UNAVAILABLE: {
            "description": "Database is locked or had trouble handling the request",
            "model": ErrorMessage,
        },
        status.HTTP_500_INTERNAL_SERVER_ERROR: {
            "description": "Internal server error",
            "model": ErrorMessage,
        },
    },
)
async def update_custom_config(
    custom_configs: Union[CustomConfigNameModel, List[CustomConfigNameModel]],
    method: str,
    background_tasks: BackgroundTasks,
    reload: bool = True,
):
    """Update one or more custom configs"""
    resp = "created"
    status_code = None

    if isinstance(custom_configs, CustomConfigNameModel):
        resp = DB.upsert_custom_config(custom_configs.model_dump() | {"method": method})

        if resp == "method_conflict":
            message = (
                f"Can't upsert custom config {custom_configs.name}"
                + (
                    f" from service {custom_configs.service_id}"
                    if custom_configs.service_id
                    else ""
                )
                + " because it was created by either the core or the autoconf and the method isn't one of them"
            )
            CORE_CONFIG.logger.warning(message)
            return JSONResponse(
                status_code=status.HTTP_403_FORBIDDEN, content={"message": message}
            )
        elif "database is locked" in resp or "file is not a database" in resp:
            retry_in = str(uniform(1.0, 5.0))
            CORE_CONFIG.logger.warning(
                f"Can't upsert custom config: Database is locked or had trouble handling the request, retry in {retry_in} seconds"
            )
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={
                    "message": f"Database is locked or had trouble handling the request, retry in {retry_in} seconds"
                },
                headers={"Retry-After": retry_in},
            )
        elif resp and resp not in ("created", "updated"):
            CORE_CONFIG.logger.error(f"Can't upsert custom config: {resp}")
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={"message": resp},
            )

        message = f"Custom config {custom_configs.name} {resp}"
    else:
        resp = DB.save_custom_configs([c.model_dump() for c in custom_configs], method)

        if "database is locked" in resp or "file is not a database" in resp:
            retry_in = str(uniform(1.0, 5.0))
            CORE_CONFIG.logger.warning(
                f"Can't upsert custom configs: Database is locked or had trouble handling the request, retry in {retry_in} seconds"
            )
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={
                    "message": f"Database is locked or had trouble handling the request, retry in {retry_in} seconds"
                },
                headers={"Retry-After": retry_in},
            )
        if resp:
            CORE_CONFIG.logger.error(f"Can't upsert custom configs: {resp}")
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={"message": resp},
            )

        message = f"Custom configs {', '.join(c.name for c in custom_configs)} {resp}"
        status_code = status.HTTP_200_OK

    CORE_CONFIG.logger.info(f"✅ {message} to database")

    if reload:
        background_tasks.add_task(send_to_instances, {"custom_configs"})

    return JSONResponse(
        status_code=status_code
        or (status.HTTP_200_OK if resp == "updated" else status.HTTP_201_CREATED),
        content={"message": message},
    )


@router.delete(
    "/{custom_config_name}",
    response_model=Dict[Literal["message"], str],
    summary="Delete a custom config",
    response_description="Message",
    responses={
        status.HTTP_404_NOT_FOUND: {
            "description": "Custom config not found",
            "model": ErrorMessage,
        },
        status.HTTP_403_FORBIDDEN: {
            "description": "Can't delete a custom config created by the core or the autoconf if the method isn't one of them",
            "model": ErrorMessage,
        },
        status.HTTP_503_SERVICE_UNAVAILABLE: {
            "description": "Database is locked or had trouble handling the request",
            "model": ErrorMessage,
        },
        status.HTTP_500_INTERNAL_SERVER_ERROR: {
            "description": "Internal server error",
            "model": ErrorMessage,
        },
    },
)
async def delete_custom_config(
    custom_config_name: str,
    custom_config: CustomConfigModel,
    method: str,
    background_tasks: BackgroundTasks,
):
    """Update a custom config"""
    resp = DB.delete_custom_config(
        custom_config.service_id, custom_config.type, custom_config_name, method
    )

    if resp == "not_found":
        message = f"Custom config {custom_config_name} not found"
        CORE_CONFIG.logger.warning(message)
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND, content={"message": message}
        )
    elif resp == "method_conflict":
        message = (
            f"Can't delete custom config {custom_config_name}"
            + (
                f" from service {custom_config.service_id}"
                if custom_config.service_id
                else ""
            )
            + " because it was created by either the core or the autoconf and the method isn't one of them"
        )
        CORE_CONFIG.logger.warning(message)
        return JSONResponse(
            status_code=status.HTTP_403_FORBIDDEN, content={"message": message}
        )
    elif "database is locked" in resp or "file is not a database" in resp:
        retry_in = str(uniform(1.0, 5.0))
        CORE_CONFIG.logger.warning(
            f"Can't delete custom config: Database is locked or had trouble handling the request, retry in {retry_in} seconds"
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "message": f"Database is locked or had trouble handling the request, retry in {retry_in} seconds"
            },
            headers={"Retry-After": retry_in},
        )
    elif resp:
        CORE_CONFIG.logger.error(f"Can't delete custom config: {resp}")
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"message": resp},
        )

    CORE_CONFIG.logger.info(
        f"✅ Custom config {custom_config_name} deleted from database"
    )

    background_tasks.add_task(send_to_instances, {"custom_configs"})

    return JSONResponse(
        content={"message": f"Custom config {custom_config_name} deleted"}
    )
