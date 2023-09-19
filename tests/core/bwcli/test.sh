#!/bin/bash

integration=$1

if [ -z "$integration" ] ; then
    echo "⌨️ Please provide an integration name as argument ❌"
    exit 1
elif [ "$integration" != "docker" ] && [ "$integration" != "linux" ] ; then
    echo "⌨️ Integration \"$integration\" is not supported ❌"
    exit 1
fi

echo "⌨️ Building bwcli stack for integration \"$integration\" ..."

# Starting stack
if [ "$integration" = "docker" ] ; then
    docker compose pull bw-docker
    if [ $? -ne 0 ] ; then
        echo "⌨️ Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.test.yml build
    if [ $? -ne 0 ] ; then
        echo "⌨️ Build failed ❌"
        exit 1
    fi
else
    sudo systemctl stop bunkerweb

    echo "⌨️ Installing Redis ..."
    sudo apt install -y redis
    redis-server --daemonize yes
    if [ $? -ne 0 ] ; then
        echo "⌨️ Redis start failed ❌"
        exit 1
    fi
    echo "⌨️ Redis installed ✅"
    
    echo "USE_REDIS=yes" | sudo tee -a /etc/bunkerweb/variables.env
    echo "REDIS_HOST=127.0.0.1" | sudo tee -a /etc/bunkerweb/variables.env
    sudo touch /var/www/html/index.html
fi

cleanup_stack () {
    echo "⌨️ Cleaning up current stack ..."

    if [ "$integration" == "docker" ] ; then
        docker compose down -v --remove-orphans
    else
        sudo systemctl stop bunkerweb
        sudo truncate -s 0 /var/log/bunkerweb/error.log
    fi

    if [ $? -ne 0 ] ; then
        echo "⌨️ Cleanup failed ❌"
        exit 1
    fi

    echo "⌨️ Cleaning up current stack done ✅"
}

# Cleanup stack on exit
trap cleanup_stack EXIT

echo "⌨️ Running bwcli tests ..."

echo "⌨️ Starting stack ..."
if [ "$integration" == "docker" ] ; then
    docker compose up -d
    if [ $? -ne 0 ] ; then
        echo "⌨️ Up failed, retrying ... ⚠️"
        manual=1
        cleanup_stack
        manual=0
        docker compose up -d
        if [ $? -ne 0 ] ; then
            echo "⌨️ Up failed ❌"
            exit 1
        fi
    fi
else
    sudo systemctl start bunkerweb
    if [ $? -ne 0 ] ; then
        echo "⌨️ Up failed ❌"
        exit 1
    fi
fi

# Check if stack is healthy
echo "⌨️ Waiting for stack to be healthy ..."
i=0
if [ "$integration" == "docker" ] ; then
    while [ $i -lt 120 ] ; do
        containers=("bwcli-bw-1" "bwcli-bw-scheduler-1")
        healthy="true"
        for container in "${containers[@]}" ; do
            check="$(docker inspect --format "{{json .State.Health }}" $container | grep "healthy")"
            if [ "$check" = "" ] ; then
                healthy="false"
                break
            fi
        done
        if [ "$healthy" = "true" ] ; then
            echo "⌨️ Docker stack is healthy ✅"
            break
        fi
        sleep 1
        i=$((i+1))
    done
    if [ $i -ge 120 ] ; then
        docker compose logs
        echo "⌨️ Docker stack is not healthy ❌"
        exit 1
    fi
else
    while [ $i -lt 120 ] ; do
        check="$(sudo cat /var/log/bunkerweb/error.log | grep "BunkerWeb is ready")"
        if ! [ -z "$check" ] ; then
            echo "⌨️ Linux stack is healthy ✅"
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
        echo "⌨️ Linux stack is not healthy ❌"
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
    echo "⌨️ Test bwcli failed ❌"
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
    echo "⌨️ Test bwcli succeeded ✅"
fi

echo "⌨️ Tests are done ! ✅"
