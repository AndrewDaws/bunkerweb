#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from abc import abstractmethod
from time import sleep
from typing import List, Literal, Optional

from Config import Config

from API import API  # type: ignore
from logger import setup_logger  # type: ignore


class Controller(Config):
    def __init__(
        self,
        ctrl_type: Literal["docker", "swarm", "kubernetes"],
        core_api: API,
        *,
        log_level: str = "INFO",
        api_token: Optional[str] = None,
        wait_retry_interval: int = 5,
    ):
        super().__init__(
            core_api,
            log_level=log_level,
            api_token=api_token,
            wait_retry_interval=wait_retry_interval,
        )
        self._type = ctrl_type
        self._instances = []
        self._services = []
        self._configs = {config_type: {} for config_type in self._supported_config_types}
        self._logger = setup_logger(f"{self._type}-controller", log_level)

    def wait(self, wait_time: int) -> list:
        all_ready = False
        while not all_ready:
            self._instances = self.get_instances()
            if not self._instances:
                self._logger.warning(
                    f"No instance found, waiting {wait_time}s ...",
                )
                sleep(wait_time)
                continue
            all_ready = True
            for instance in self._instances:
                if not instance["health"]:
                    self._logger.warning(
                        f"Instance {instance['name']} is not ready, waiting {wait_time}s ...",
                    )
                    sleep(wait_time)
                    all_ready = False
                    break
        return self._instances

    @abstractmethod
    def _get_controller_instances(self) -> list:
        pass

    @abstractmethod
    def _to_instances(self, controller_instance) -> List[dict]:
        pass

    def get_instances(self):
        instances = []
        for controller_instance in self._get_controller_instances():
            instances.extend(self._to_instances(controller_instance))
        return instances

    @abstractmethod
    def _get_controller_services(self) -> list:
        pass

    @abstractmethod
    def _to_services(self, controller_service) -> List[dict]:
        pass

    @abstractmethod
    def _get_static_services(self) -> List[dict]:
        pass

    def get_services(self):
        services = []
        for controller_service in self._get_controller_services():
            services.extend(self._to_services(controller_service))
        services.extend(self._get_static_services())
        return services

    @abstractmethod
    def get_configs(self):
        pass

    @abstractmethod
    def apply_config(self):
        pass

    @abstractmethod
    def process_events(self):
        pass

    def _is_service_present(self, server_name):
        for service in self._services:
            if "SERVER_NAME" not in service or not service["SERVER_NAME"]:
                continue
            if server_name == service["SERVER_NAME"].strip().split()[0]:
                return True
        return False
