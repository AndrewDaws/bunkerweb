from logging import info as log_info, exception as log_exception, warning as log_warning

from selenium.webdriver.common.by import By
from selenium.common.exceptions import TimeoutException

from wizard import DRIVER
from base import TEST_TYPE
from utils import access_page, assert_alert_message, safe_get_element, wait_for_service

exit_code = 0

try:
    log_info("Navigating to the instances page ...")
    access_page(DRIVER, "/html/body/aside[1]/div[1]/div[3]/ul/li[2]/a", "instances")

    no_errors = True
    retries = 0
    action = "reload" if TEST_TYPE == "docker" else "restart"
    while no_errors:
        log_info(f"Trying to {action} BunkerWeb instance ...")

        try:
            form = safe_get_element(DRIVER, By.XPATH, "//form[starts-with(@id, 'form-instance-')]")
        except TimeoutException:
            log_exception("No instance form found, exiting ...")
            exit(1)

        try:
            access_page(DRIVER, f"//form[starts-with(@id, 'form-instance-')]//button[@value='{action}']", "instances", False)

            log_info(f"Instance was {action}ed successfully, checking the message ...")
            assert_alert_message(DRIVER, f"has been {action}ed")
            no_errors = False
        except:
            if retries >= 3:
                exit(1)
            retries += 1
            log_warning("Message list doesn't contain the expected message or is empty, retrying...")

    if TEST_TYPE == "linux":
        wait_for_service()

    log_info("✅ Instances page tests finished successfully")
except SystemExit as e:
    exit_code = e.code
except KeyboardInterrupt:
    exit_code = 1
except:
    log_exception("Something went wrong, exiting ...")
    DRIVER.save_screenshot("error.png")
    exit_code = 1
finally:
    DRIVER.quit()
    exit(exit_code)
