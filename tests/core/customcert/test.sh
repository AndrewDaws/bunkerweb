#!/bin/bash

integration=$1

if [ -z "$integration" ] ; then
    echo "🔏 Please provide an integration name as argument ❌"
    exit 1
elif [ "$integration" != "docker" ] && [ "$integration" != "linux" ] ; then
    echo "🔏 Integration \"$integration\" is not supported ❌"
    exit 1
fi

echo "🔏 Building customcert stack for integration \"$integration\" ..."

# Starting stack
if [ "$integration" = "docker" ] ; then
    docker compose pull bw-docker
    if [ $? -ne 0 ] ; then
        echo "🔏 Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.test.yml build
    if [ $? -ne 0 ] ; then
        echo "🔏 Build failed ❌"
        exit 1
    fi
else
    sudo systemctl stop bunkerweb
    echo "USE_CUSTOM_SSL=no" | sudo tee -a /etc/bunkerweb/variables.env
    echo "CUSTOM_SSL_CERT=/tmp/certificate.pem" | sudo tee -a /etc/bunkerweb/variables.env
    echo "CUSTOM_SSL_KEY=/tmp/privatekey.key" | sudo tee -a /etc/bunkerweb/variables.env
    sudo touch /var/www/html/index.html
fi

manual=0
end=0
cleanup_stack () {
    exit_code=$?
    if [[ $end -eq 1 || $exit_code = 1 ]] || [[ $end -eq 0 && $exit_code = 0 ]] && [ $manual = 0 ] ; then
        if [ "$integration" == "docker" ] ; then
            rm -rf init/certs
            find . -type f -name 'docker-compose.*' -exec sed -i 's@USE_CUSTOM_SSL: "yes"@USE_CUSTOM_SSL: "no"@' {} \;
        else
            sudo rm -f /tmp/certificate.pem /tmp/privatekey.key
            sudo sed -i 's@USE_CUSTOM_SSL=.*$@USE_CUSTOM_SSL=no@' /etc/bunkerweb/variables.env
            unset USE_CUSTOM_SSL
            unset CUSTOM_SSL_CERT
            unset CUSTOM_SSL_KEY
        fi
        if [[ $end -eq 1 && $exit_code = 0 ]] ; then
            return
        fi
    fi

    echo "🔏 Cleaning up current stack ..."

    if [ "$integration" == "docker" ] ; then
        docker compose down -v --remove-orphans
    else
        sudo systemctl stop bunkerweb
        sudo truncate -s 0 /var/log/bunkerweb/error.log
    fi

    if [ $? -ne 0 ] ; then
        echo "🔏 Cleanup failed ❌"
        exit 1
    fi

    echo "🔏 Cleaning up current stack done ✅"
}

# Cleanup stack on exit
trap cleanup_stack EXIT

if [ "$integration" == "docker" ] ; then
    echo "🔏 Initializing workspace ..."
    rm -rf init/certs
    mkdir -p init/certs
    docker compose -f docker-compose.init.yml up --build
    if [ $? -ne 0 ] ; then
        echo "🔏 Build failed ❌"
        exit 1
    elif ! [[ -f "init/certs/certificate.pem" ]]; then
        echo "🔏 certificate.pem not found ❌"
        exit 1
    elif ! [[ -f "init/certs/privatekey.key" ]]; then
        echo "🔏 privatekey.key not found ❌"
        exit 1
    fi
else
    echo "🔏 Generating certificate for www.example.com ..."
    openssl req -nodes -x509 -newkey rsa:4096 -keyout /tmp/privatekey.key -out /tmp/certificate.pem -days 365 -subj /CN=www.example.com/
    if [ $? -ne 0 ] ; then
        echo "🔏 Certificate generation failed ❌"
        exit 1
    fi
    sudo chmod 777 /tmp/privatekey.key /tmp/certificate.pem
fi

for test in "deactivated" "activated"
do
    if [ "$test" = "deactivated" ] ; then
        echo "🔏 Running tests without the custom cert ..."
    elif [ "$test" = "activated" ] ; then
        echo "🔏 Running tests with the custom cert activated ..."
        if [ "$integration" == "docker" ] ; then
            find . -type f -name 'docker-compose.*' -exec sed -i 's@USE_CUSTOM_SSL: "no"@USE_CUSTOM_SSL: "yes"@' {} \;
        else
            sudo sed -i 's@USE_CUSTOM_SSL=.*$@USE_CUSTOM_SSL=yes@' /etc/bunkerweb/variables.env
            export USE_CUSTOM_SSL="yes"
        fi
    fi

    echo "🔏 Starting stack ..."
    if [ "$integration" == "docker" ] ; then
        docker compose up -d
        if [ $? -ne 0 ] ; then
            echo "🔏 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            manual=0
            docker compose up -d
            if [ $? -ne 0 ] ; then
                echo "🔏 Up failed ❌"
                exit 1
            fi
        fi
    else
        sudo systemctl start bunkerweb
        if [ $? -ne 0 ] ; then
            echo "🔏 Start failed ❌"
            exit 1
        fi
    fi

    # Check if stack is healthy
    echo "🔏 Waiting for stack to be healthy ..."
    i=0
    if [ "$integration" == "docker" ] ; then
        while [ $i -lt 120 ] ; do
            containers=("customcert-bw-1" "customcert-bw-scheduler-1")
            healthy="true"
            for container in "${containers[@]}" ; do
                check="$(docker inspect --format "{{json .State.Health }}" $container | grep "healthy")"
                if [ "$check" = "" ] ; then
                    healthy="false"
                    break
                fi
            done
            if [ "$healthy" = "true" ] ; then
                echo "🔏 Docker stack is healthy ✅"
                break
            fi
            sleep 1
            i=$((i+1))
        done
        if [ $i -ge 120 ] ; then
            docker compose logs
            echo "🔏 Docker stack is not healthy ❌"
            exit 1
        fi
    else
        while [ $i -lt 120 ] ; do
            check="$(sudo cat /var/log/bunkerweb/error.log | grep "BunkerWeb is ready")"
            if ! [ -z "$check" ] ; then
                echo "🔏 Linux stack is healthy ✅"
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
            echo "🔏 Linux stack is not healthy ❌"
            exit 1
        fi
    fi

    # Start tests

    if [ "$integration" == "docker" ] ; then
        docker compose -f docker-compose.test.yml up --abort-on-container-exit --exit-code-from tests
    else
        python3 main.py
    fi

    if [ $? -ne 0 ] ; then
        echo "🔏 Test \"$test\" failed ❌"
        echo "🛡️ Showing BunkerWeb and BunkerWeb Scheduler logs ..."
        if [ "$integration" == "docker" ] ; then
            docker compose logs bw bw-scheduler
        else
            sudo journalctl -u bunkerweb --no-pager
            echo "🛡️ Showing BunkerWeb error logs ..."
            sudo cat /var/log/bunkerweb/error.log
            echo "🛡️ Showing BunkerWeb access logs ..."
            sudo cat /var/log/bunkerweb/access.log
        fi
        exit 1
    else
        echo "🔏 Test \"$test\" succeeded ✅"
    fi

    manual=1
    cleanup_stack
    manual=0

    echo " "
done

end=1
echo "🔏 Tests are done ! ✅"
