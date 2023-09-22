#!/bin/bash

integration=$1

if [ -z "$integration" ] ; then
    echo "🧳 Please provide an integration name as argument ❌"
    exit 1
elif [ "$integration" != "docker" ] && [ "$integration" != "linux" ] ; then
    echo "🧳 Integration \"$integration\" is not supported ❌"
    exit 1
fi

echo "🧳 Building sessions stack for integration \"$integration\" ..."

# Starting stack
if [ "$integration" = "docker" ] ; then
    docker compose pull bw-docker
    if [ $? -ne 0 ] ; then
        echo "🧳 Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.test.yml build
    if [ $? -ne 0 ] ; then
        echo "🧳 Build failed ❌"
        exit 1
    fi
else
    sudo systemctl stop bunkerweb
    sudo pip install -r requirements.txt
    echo "USE_ANTIBOT=cookie" | sudo tee -a /etc/bunkerweb/variables.env
    echo "SESSIONS_SECRET=random" | sudo tee -a /etc/bunkerweb/variables.env
    echo "SESSIONS_NAME=random" | sudo tee -a /etc/bunkerweb/variables.env
    sudo touch /var/www/html/index.html
    export TEST_TYPE="linux"
fi

manual=0
end=0
cleanup_stack () {
    exit_code=$?
    if [[ $end -eq 1 || $exit_code = 1 ]] || [[ $end -eq 0 && $exit_code = 0 ]] && [ $manual = 0 ] ; then
        if [ "$integration" = "docker" ] ; then
            find . -type f -name 'docker-compose.*' -exec sed -i 's@SESSIONS_SECRET: ".*"$@SESSIONS_SECRET: "random"@' {} \;
            find . -type f -name 'docker-compose.*' -exec sed -i 's@SESSIONS_NAME: ".*"$@SESSIONS_NAME: "random"@' {} \;
        else
            sudo sed -i 's@SESSIONS_SECRET=.*$@SESSIONS_SECRET=random@' /etc/bunkerweb/variables.env
            sudo sed -i 's@SESSIONS_NAME=.*$@SESSIONS_NAME=random@' /etc/bunkerweb/variables.env
            unset SESSIONS_SECRET
            unset SESSIONS_NAME
        fi
        if [[ $end -eq 1 && $exit_code = 0 ]] ; then
            return
        fi
    fi

    echo "🧳 Cleaning up current stack ..."

    if [ "$integration" == "docker" ] ; then
        docker compose down -v --remove-orphans
    else
        sudo systemctl stop bunkerweb
        sudo truncate -s 0 /var/log/bunkerweb/error.log
    fi

    if [ $? -ne 0 ] ; then
        echo "🧳 Cleanup failed ❌"
        exit 1
    fi

    echo "🧳 Cleaning up current stack done ✅"
}

# Cleanup stack on exit
trap cleanup_stack EXIT

for test in "random" "manual_name" # TODO: "manual_secret"
do
    if [ "$test" = "random" ] ; then
        echo "🧳 Running tests with random secret and random name ..."
    elif [ "$test" = "manual_name" ] ; then
        echo "🧳 Running tests where session name is equal to \"test\" ..."
        if [ "$integration" == "docker" ] ; then
            find . -type f -name 'docker-compose.*' -exec sed -i 's@SESSIONS_NAME: ".*"$@SESSIONS_NAME: "test"@' {} \;
        else
            sudo sed -i 's@SESSIONS_NAME=.*$@SESSIONS_NAME=test@' /etc/bunkerweb/variables.env
            export SESSIONS_NAME="test"
        fi
    elif [ "$test" = "manual_secret" ] ; then
        echo "🧳 Running tests where session secret is equal to \"test\" ..."
        if [ "$integration" == "docker" ] ; then
            find . -type f -name 'docker-compose.*' -exec sed -i 's@SESSIONS_NAME: ".*"$@SESSIONS_NAME: "random"@' {} \;
            find . -type f -name 'docker-compose.*' -exec sed -i 's@SESSIONS_SECRET: ".*"$@SESSIONS_SECRET: "test"@' {} \;
        else
            sudo sed -i 's@SESSIONS_NAME=.*$@SESSIONS_NAME=random@' /etc/bunkerweb/variables.env
            sudo sed -i 's@SESSIONS_SECRET=.*$@SESSIONS_SECRET=test@' /etc/bunkerweb/variables.env
            unset SESSIONS_NAME
            export SESSIONS_SECRET="test"
        fi
    fi

    echo "🧳 Starting stack ..."
    if [ "$integration" == "docker" ] ; then
        docker compose up -d
        if [ $? -ne 0 ] ; then
            echo "🧳 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            manual=0
            docker compose up -d
            if [ $? -ne 0 ] ; then
                echo "🧳 Up failed ❌"
                exit 1
            fi
        fi
    else
        sudo systemctl start bunkerweb
        if [ $? -ne 0 ] ; then
            echo "🧳 Start failed ❌"
            exit 1
        fi
    fi

    # Check if stack is healthy
    echo "🧳 Waiting for stack to be healthy ..."
    i=0
    if [ "$integration" == "docker" ] ; then
        while [ $i -lt 120 ] ; do
            containers=("sessions-bw-1" "sessions-bw-scheduler-1")
            healthy="true"
            for container in "${containers[@]}" ; do
                check="$(docker inspect --format "{{json .State.Health }}" $container | grep "healthy")"
                if [ "$check" = "" ] ; then
                    healthy="false"
                    break
                fi
            done
            if [ "$healthy" = "true" ] ; then
                echo "🧳 Docker stack is healthy ✅"
                break
            fi
            sleep 1
            i=$((i+1))
        done
        if [ $i -ge 120 ] ; then
            docker compose logs
            echo "🧳 Docker stack is not healthy ❌"
            exit 1
        fi
    else
        while [ $i -lt 120 ] ; do
            check="$(sudo cat /var/log/bunkerweb/error.log | grep "BunkerWeb is ready")"
            if ! [ -z "$check" ] ; then
                echo "🧳 Linux stack is healthy ✅"
                break
            fi
            sleep 1
            i=$((i+1))
        done
        if [ $i -ge 120 ] ; then
            sudo journalctl -u bunkerweb --no-pager
            echo "🛡️ Showing BunkerWeb error logs ..."
            sudo cat /var/log/bunkerweb/error.log
            echo "🛡️ Showing BunkerWeb access logs ..."
            sudo cat /var/log/bunkerweb/access.log
            echo "🧳 Linux stack is not healthy ❌"
            exit 1
        fi
    fi

    # Start tests

    if [ "$integration" == "docker" ] ; then
        docker compose -f docker-compose.test.yml up --abort-on-container-exit --exit-code-from tests
    else
        sudo -E python3 main.py
    fi

    if [ $? -ne 0 ] ; then
        echo "🧳 Test \"$test\" failed ❌"
        echo "🛡️ Showing BunkerWeb and BunkerWeb Scheduler logs ..."
        if [ "$integration" == "docker" ] ; then
            docker compose logs bw bw-scheduler
        else
            sudo journalctl -u bunkerweb --no-pager
            echo "🛡️ Showing BunkerWeb error logs ..."
            sudo cat /var/log/bunkerweb/error.log
            echo "🛡️ Showing BunkerWeb access logs ..."
            sudo cat /var/log/bunkerweb/access.log
            echo "🛡️ Showing Geckodriver logs ..."
            sudo cat geckodriver.log
        fi
        exit 1
    else
        echo "🧳 Test \"$test\" succeeded ✅"
    fi

    manual=1
    cleanup_stack
    manual=0

    echo " "
done

end=1
echo "🧳 Tests are done ! ✅"
