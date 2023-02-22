from pathlib import Path
from subprocess import run
from typing import Any, Optional, Union

from API import API
from ApiCaller import ApiCaller


class Instance:
    _id: str
    name: str
    hostname: str
    _type: str
    health: bool
    env: Any
    apiCaller: ApiCaller

    def __init__(
        self,
        _id: str,
        name: str,
        hostname: str,
        _type: str,
        status: str,
        data: Any = None,
        apiCaller: Optional[ApiCaller] = None,
    ) -> None:
        self._id = _id
        self.name = name
        self.hostname = hostname
        self._type = _type
        self.health = status == "up" and (
            (
                data.attrs["State"]["Health"]["Status"] == "healthy"
                if "Health" in data.attrs["State"]
                else False
            )
            if _type == "container" and data
            else True
        )
        self.env = data
        self.apiCaller = apiCaller or ApiCaller()

    def get_id(self) -> str:
        return self._id

    def reload(self) -> bool:
        return self.apiCaller._send_to_apis("POST", "/reload")

    def start(self) -> bool:
        return self.apiCaller._send_to_apis("POST", "/start")

    def stop(self) -> bool:
        return self.apiCaller._send_to_apis("POST", "/stop")

    def restart(self) -> bool:
        return self.apiCaller._send_to_apis("POST", "/restart")


class Instances:
    def __init__(self, docker_client, kubernetes_client, integration: str):
        self.__docker_client = docker_client
        self.__kubernetes_client = kubernetes_client
        self.__integration = integration

    def __instance_from_id(self, _id) -> Instance:
        instances: list[Instance] = self.get_instances()
        for instance in instances:
            if instance._id == _id:
                return instance

        raise Exception(f"Can't find instance with id {_id}")

    def get_instances(self) -> list[Instance]:
        instances = []
        # Docker instances (containers or services)
        if self.__docker_client is not None:
            for instance in self.__docker_client.containers.list(
                all=True, filters={"label": "bunkerweb.INSTANCE"}
            ):
                env_variables = {
                    x[0]: x[1]
                    for x in [env.split("=") for env in instance.attrs["Config"]["Env"]]
                }

                apiCaller = ApiCaller()
                apiCaller._set_apis(
                    [
                        API(
                            f"http://{instance.name}:{env_variables.get('API_HTTP_PORT', '5000')}",
                            env_variables.get("API_SERVER_NAME", "bwapi"),
                        )
                    ]
                )

                instances.append(
                    Instance(
                        instance.id,
                        instance.name,
                        instance.name,
                        "container",
                        "up" if instance.status == "running" else "down",
                        instance,
                        apiCaller,
                    )
                )
        elif self.__integration == "Swarm":
            for instance in self.__docker_client.services.list(
                filters={"label": "bunkerweb.INSTANCE"}
            ):
                status = "down"
                desired_tasks = instance.attrs["ServiceStatus"]["DesiredTasks"]
                running_tasks = instance.attrs["ServiceStatus"]["RunningTasks"]
                if desired_tasks > 0 and (desired_tasks == running_tasks):
                    status = "up"

                instances.append(
                    Instance(
                        instance.id,
                        instance.name,
                        instance.name,
                        "service",
                        status,
                        instance,
                        None,
                    )
                )
        elif self.__integration == "Kubernetes":
            for pod in self.__kubernetes_client.list_pod_for_all_namespaces(
                watch=False
            ).items:
                if (
                    pod.metadata.annotations != None
                    and "bunkerweb.io/INSTANCE" in pod.metadata.annotations
                ):
                    env_variables = {
                        e.name: e.value for e in pod.spec.containers[0].env
                    }

                    apiCaller = ApiCaller()
                    apiCaller._set_apis(
                        [
                            API(
                                f"http://{pod.status.pod_ip}:{env_variables.get('API_HTTP_PORT', '5000')}",
                                env_variables.get("API_SERVER_NAME", "bwapi"),
                            )
                        ]
                    )

                    status = "up"
                    if pod.status.conditions is not None:
                        for condition in pod.status.conditions:
                            if condition.type == "Ready" and condition.status == "True":
                                status = "down"
                                break

                    instances.append(
                        Instance(
                            pod.metadata.uid,
                            pod.metadata.name,
                            pod.status.pod_ip,
                            "pod",
                            status,
                            pod,
                            apiCaller,
                        )
                    )

        instances = sorted(
            instances,
            key=lambda x: x.name,
        )

        # Local instance
        if Path("/usr/sbin/nginx").exists():
            instances.insert(
                0,
                Instance(
                    "local",
                    "local",
                    "127.0.0.1",
                    "local",
                    "up" if Path("/var/tmp/bunkerweb/nginx.pid").exists() else "down",
                ),
            )

        return instances

    def reload_instances(self) -> Union[list[str], str]:
        not_reloaded: list[str] = []
        for instance in self.get_instances():
            if instance.health is False:
                not_reloaded.append(instance.name)
                continue

            if self.reload_instance(instance=instance).startswith("Can't reload"):
                not_reloaded.append(instance.name)

        return not_reloaded or "Successfully reloaded instances"

    def reload_instance(
        self, id: Optional[int] = None, instance: Optional[Instance] = None
    ) -> str:
        if instance is None:
            instance = self.__instance_from_id(id)

        result = True
        if instance._type == "local":
            result = (
                run(
                    ["sudo", "systemctl", "restart", "bunkerweb"], capture_output=True
                ).returncode
                != 0
            )
        elif instance._type == "container":
            # result = instance.run_jobs()
            result = result & instance.reload()

        if result:
            return f"Instance {instance.name} has been reloaded."

        return f"Can't reload {instance.name}"

    def start_instance(self, id) -> str:
        instance = self.__instance_from_id(id)
        result = True

        if instance._type == "local":
            proc = run(
                ["sudo", "/usr/share/bunkerweb/ui/linux.sh", "start"],
                capture_output=True,
            )
            result = proc.returncode == 0
        elif instance._type == "container":
            result = instance.start()

        if result:
            return f"Instance {instance.name} has been started."

        return f"Can't start {instance.name}"

    def stop_instance(self, id) -> str:
        instance = self.__instance_from_id(id)
        result = True

        if instance._type == "local":
            proc = run(
                ["sudo", "/usr/share/bunkerweb/ui/linux.sh", "stop"],
                capture_output=True,
            )
            result = proc.returncode == 0
        elif instance._type == "container":
            result = instance.stop()

        if result:
            return f"Instance {instance.name} has been stopped."

        return f"Can't stop {instance.name}"

    def restart_instance(self, id) -> str:
        instance = self.__instance_from_id(id)
        result = True

        if instance._type == "local":
            proc = run(
                ["sudo", "/usr/share/bunkerweb/ui/linux.sh", "restart"],
                capture_output=True,
            )
            result = proc.returncode == 0
        elif instance._type == "container":
            result = instance.restart()

        if result:
            return f"Instance {instance.name} has been restarted."

        return f"Can't restart {instance.name}"
