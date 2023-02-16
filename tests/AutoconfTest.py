from Test import Test
from os.path import isdir, isfile
from os import getenv
from shutil import copytree, rmtree
from traceback import format_exc
from subprocess import run
from time import sleep
from logger import setup_logger


class AutoconfTest(Test):
    def __init__(self, name, timeout, tests, no_copy_container=False, delay=0):
        super().__init__(
            name,
            "autoconf",
            timeout,
            tests,
            no_copy_container=no_copy_container,
            delay=delay,
        )
        self._domains = {
            r"www\.example\.com": getenv("TEST_DOMAIN1"),
            r"auth\.example\.com": getenv("TEST_DOMAIN1"),
            r"app1\.example\.com": getenv("TEST_DOMAIN1_1"),
            r"app2\.example\.com": getenv("TEST_DOMAIN1_2"),
            r"app3\.example\.com": getenv("TEST_DOMAIN1_3"),
        }
        self.__logger = setup_logger("Autoconf_test", getenv("LOG_LEVEL", "INFO"))

    @staticmethod
    def init():
        try:
            if not Test.init():
                return False
            proc = run("sudo chown -R root:root /tmp/bw-data", shell=True)
            if proc.returncode != 0:
                raise (Exception("chown failed (autoconf stack)"))
            if isdir("/tmp/autoconf"):
                rmtree("/tmp/autoconf")
            copytree("./integrations/autoconf", "/tmp/autoconf")
            compose = "/tmp/autoconf/docker-compose.yml"
            Test.replace_in_file(
                compose, r"bunkerity/bunkerweb:.*$", "10.20.1.1:5000/bw-tests:latest"
            )
            Test.replace_in_file(
                compose,
                r"bunkerity/bunkerweb-autoconf:.*$",
                "10.20.1.1:5000/bw-autoconf-tests:latest",
            )
            Test.replace_in_file(compose, r"\./bw\-data:/", "/tmp/bw-data:/")
            proc = run(
                "docker-compose pull --ignore-pull-failures",
                cwd="/tmp/autoconf",
                shell=True,
            )
            if proc.returncode != 0:
                raise (Exception("docker-compose pull failed (autoconf stack)"))
            proc = run("docker-compose up -d", cwd="/tmp/autoconf", shell=True)
            if proc.returncode != 0:
                raise (Exception("docker-compose up failed (autoconf stack)"))
            i = 0
            healthy = False
            while i < 30:
                proc = run(
                    'docker inspect --format "{{json .State.Health }}" autoconf_mybunker_1',
                    cwd="/tmp/autoconf",
                    shell=True,
                    capture_output=True,
                )
                if proc.returncode != 0:
                    raise (Exception("docker-compose inspect failed (autoconf stack)"))
                if "healthy" in proc.stdout.decode():
                    healthy = True
                    break
                sleep(1)
                i += 1
            if not healthy:
                raise (Exception("autoconf stack is not healthy"))
        except:
            setup_logger("Autoconf_test", getenv("LOG_LEVEL", "INFO")).error(
                f"exception while running AutoconfTest.init()\n{format_exc()}",
            )
            return False
        return True

    @staticmethod
    def end():
        ret = True
        try:
            if not Test.end():
                return False
            proc = run("docker-compose down -v", cwd="/tmp/autoconf", shell=True)
            if proc.returncode != 0:
                ret = False
            rmtree("/tmp/autoconf")
        except:
            setup_logger("Autoconf_test", getenv("LOG_LEVEL", "INFO")).error(
                f"exception while running AutoconfTest.end()\n{format_exc()}",
            )
            return False
        return ret

    def _setup_test(self):
        try:
            super()._setup_test()
            test = f"/tmp/tests/{self._name}"
            compose = f"/tmp/tests/{self._name}/autoconf.yml"
            example_data = f"/tmp/tests/{self._name}/bw-data"
            Test.replace_in_file(
                compose, r"bunkerity/bunkerweb:.*$", "10.20.1.1:5000/bw-tests:latest"
            )
            Test.replace_in_file(compose, r"\./bw\-data:/", "/tmp/bw-data:/")
            Test.replace_in_file(compose, r"\- bw_data:/", "- /tmp/bw-data:/")
            for ex_domain, test_domain in self._domains.items():
                Test.replace_in_files(test, ex_domain, test_domain)
                Test.rename(test, ex_domain, test_domain)
            Test.replace_in_files(test, "example.com", getenv("ROOT_DOMAIN"))
            setup = f"{test}/setup-autoconf.sh"
            if isfile(setup):
                proc = run("sudo ./setup-autoconf.sh", cwd=test, shell=True)
                if proc.returncode != 0:
                    raise (Exception("setup-autoconf failed"))
            if isdir(example_data) and not self._no_copy_container:
                proc = run(
                    f"sudo bash -c 'cp -rp {example_data}/* /tmp/bw-data'",
                    shell=True,
                )
                if proc.returncode != 0:
                    raise (Exception("cp bw-data failed"))
            proc = run(
                "docker-compose -f autoconf.yml pull --ignore-pull-failures",
                shell=True,
                cwd=test,
            )
            if proc.returncode != 0:
                raise (Exception("docker-compose pull failed"))
            proc = run("docker-compose -f autoconf.yml up -d", shell=True, cwd=test)
            if proc.returncode != 0:
                raise (Exception("docker-compose up failed"))
        except:
            self.__logger.error(
                f"exception while running AutoconfTest._setup_test()\n{format_exc()}",
            )
            self._cleanup_test()
            return False
        return True

    def _cleanup_test(self):
        try:
            test = f"/tmp/tests/{self._name}"
            proc = run("docker-compose -f autoconf.yml down -v", shell=True, cwd=test)
            if proc.returncode != 0:
                raise (Exception("docker-compose down failed"))
            super()._cleanup_test()
        except:
            self.__logger.error(
                f"exception while running AutoconfTest._cleanup_test()\n{format_exc()}",
            )
            return False
        return True

    def _debug_fail(self):
        autoconf = "/tmp/autoconf"
        proc = run("docker-compose logs", shell=True, cwd=autoconf)
        if proc.returncode != 0:
            raise (Exception("docker-compose logs failed"))
        test = f"/tmp/tests/{self._name}"
        proc = run("docker-compose -f autoconf.yml logs", shell=True, cwd=test)
        if proc.returncode != 0:
            raise (Exception("docker-compose -f autoconf.yml logs failed"))
