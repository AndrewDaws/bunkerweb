#!/bin/bash

integration=$1

if [ -z "$integration" ] ; then
    echo "💾 Please provide an integration name as argument ❌"
    exit 1
elif [ "$integration" != "docker" ] && [ "$integration" != "linux" ] ; then
    echo "💾 Integration \"$integration\" is not supported ❌"
    exit 1
fi

echo "💾 Building db stack for integration \"$integration\" ..."

# Starting stack
if [ "$integration" == "docker" ] ; then
    docker compose pull bw-docker app1
    if [ $? -ne 0 ] ; then
        echo "💾 Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.mariadb.yml pull bw-db
    if [ $? -ne 0 ] ; then
        echo "💾 Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.mysql.yml pull bw-db
    if [ $? -ne 0 ] ; then
        echo "💾 Pull failed ❌"
        exit 1
    fi
    docker compose -f docker-compose.postgres.yml pull bw-db
    if [ $? -ne 0 ] ; then
        echo "💾 Pull failed ❌"
        exit 1
    fi
else
    sudo systemctl stop bunkerweb
    MAKEFLAGS="-j $(nproc)" sudo pip install --no-cache-dir --require-hashes -r requirements.txt
    sudo sed -i 's@SERVER_NAME=.*$@SERVER_NAME=bwadm.example.com@' /etc/bunkerweb/variables.env
    echo "MULTISITE=no" | sudo tee -a /etc/bunkerweb/variables.env
    echo "USE_REVERSE_PROXY=yes" | sudo tee -a /etc/bunkerweb/variables.env
    echo "REVERSE_PROXY_HOST=http://app1:8080" | sudo tee -a /etc/bunkerweb/variables.env
    echo "REVERSE_PROXY_URL=/" | sudo tee -a /etc/bunkerweb/variables.env
    echo "DATABASE_URI=sqlite:////var/lib/bunkerweb/db.sqlite3" | sudo tee -a /etc/bunkerweb/variables.env
    echo 'SecRule REQUEST_FILENAME "@rx ^/db" "id:10000,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog"' | sudo tee /etc/bunkerweb/configs/modsec/test_custom_conf.conf
    sudo chown -R nginx:nginx /etc/bunkerweb
    sudo chmod 777 /etc/bunkerweb/configs/modsec/test_custom_conf.conf
    sudo touch /var/www/html/index.html

    export TEST_TYPE="linux"
    export GLOBAL_SERVER_NAME="bwadm.example.com"
    export GLOBAL_HTTP_PORT="80"
    export GLOBAL_HTTPS_PORT="443"
    export GLOBAL_DNS_RESOLVERS="9.9.9.9 8.8.8.8 8.8.4.4"
    export GLOBAL_LOG_LEVEL="info"
    export GLOBAL_USE_BUNKERNET="no"
    export GLOBAL_USE_BLACKLIST="no"
    export GLOBAL_USE_REVERSE_PROXY="yes"
    export GLOBAL_REVERSE_PROXY_HOST="http://app1:8080"
    export GLOBAL_REVERSE_PROXY_URL="/"
    export CUSTOM_CONF_MODSEC_test_custom_conf='SecRule REQUEST_FILENAME "@rx ^/db" "id:10000,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog"'
fi

manual=0
end=0
cleanup_stack () {
    exit_code=$?
    if [[ $end -eq 1 || $exit_code = 1 ]] || [[ $end -eq 0 && $exit_code = 0 ]] && [ $manual = 0 ] ; then
        if [ "$integration" == "docker" ] ; then
            rm -rf init/plugins
            rm -rf init/bunkerweb
            find . -type f -name 'docker-compose.*' -exec sed -i 's@DATABASE_URI: ".*"$@DATABASE_URI: "sqlite:////var/lib/bunkerweb/db.sqlite3"@' {} \;
            find . -type f -name 'docker-compose.*' -exec sed -i 's@MULTISITE: "yes"$@MULTISITE: "no"@' {} \;
            sed -i 's@bwadm.example.com_USE_REVERSE_PROXY@USE_REVERSE_PROXY@' docker-compose.yml
            sed -i 's@bwadm.example.com_REVERSE_PROXY_HOST@REVERSE_PROXY_HOST@' docker-compose.yml
            sed -i 's@bwadm.example.com_REVERSE_PROXY_URL@REVERSE_PROXY_URL@' docker-compose.yml
            sed -i 's@SERVICE_USE_REVERSE_PROXY@GLOBAL_USE_REVERSE_PROXY@' docker-compose.test.yml
            sed -i 's@SERVICE_REVERSE_PROXY_HOST@GLOBAL_REVERSE_PROXY_HOST@' docker-compose.test.yml
            sed -i 's@SERVICE_REVERSE_PROXY_URL@GLOBAL_REVERSE_PROXY_URL@' docker-compose.test.yml

            if [[ $(sed '16!d' docker-compose.yml) = '      bwadm.example.com_SERVER_NAME: "bwadm.example.com"' ]] ; then
                sed -i '16d' docker-compose.yml
            fi

            if [[ $(sed '20!d' docker-compose.yml) = "      bwadm.example.com_CUSTOM_CONF_MODSEC_CRS_test_service_conf: 'SecRule REQUEST_FILENAME \"@rx ^/test\" \"id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog\"'" ]] ; then
                sed -i '20d' docker-compose.yml
            fi

            if [[ $(sed '16!d' docker-compose.test.yml) = '      SERVICE_SERVER_NAME: "bwadm.example.com"' ]] ; then
                sed -i '16d' docker-compose.test.yml
            fi

            if [[ $(sed '20!d' docker-compose.test.yml) = "      CUSTOM_CONF_SERVICE_MODSEC_CRS_test_service_conf: 'SecRule REQUEST_FILENAME \"@rx ^/test\" \"id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog\"'" ]] ; then
                sed -i '20d' docker-compose.test.yml
            fi
        else
            sudo rm -rf /etc/bunkerweb/plugins/*
            sudo sed -i 's@MULTISITE=.*$@MULTISITE=no@' /etc/bunkerweb/variables.env
            sudo sed -i 's@DATABASE_URI=.*$@DATABASE_URI=sqlite:////var/lib/bunkerweb/db.sqlite3@' /etc/bunkerweb/variables.env
            sudo sed -i 's@bwadm.example.com_@@g' /etc/bunkerweb/variables.env

            if [[ $(sudo tail -n 1 /etc/bunkerweb/variables.env) = "SERVER_NAME=bwadm.example.com" ]] ; then
                sudo sed -i '$ d' /etc/bunkerweb/variables.env
            fi

            unset GLOBAL_MULTISITE
            unset SERVICE_USE_REVERSE_PROXY
            unset SERVICE_REVERSE_PROXY_HOST
            unset SERVICE_REVERSE_PROXY_URL
            unset CUSTOM_CONF_SERVICE_MODSEC_CRS_test_service_conf
            export GLOBAL_USE_REVERSE_PROXY="yes"
            export GLOBAL_REVERSE_PROXY_HOST="http://app1:8080"
            export GLOBAL_REVERSE_PROXY_URL="/"
            sudo rm -f /etc/bunkerweb/configs/modsec-crs/bwadm.example.com/test_service_conf.conf
        fi
        if [[ $end -eq 1 && $exit_code = 0 ]] ; then
            return
        fi
    fi

    echo "💾 Cleaning up current stack ..."

    if [ "$integration" == "docker" ] ; then
        docker compose down -v --remove-orphans
    else
        sudo systemctl stop bunkerweb
        sudo truncate -s 0 /var/log/bunkerweb/error.log
    fi

    if [ $? -ne 0 ] ; then
        echo "💾 Cleanup failed ❌"
        exit 1
    fi

    echo "💾 Cleaning up current stack done ✅"
}

# Cleanup stack on exit
trap cleanup_stack EXIT

echo "💾 Initializing workspace ..."
if [ "$integration" == "docker" ] ; then
    echo "💾 Creating the bw-docker network ..."
    docker network create bw-docker

    echo "💾 Starting stack ..."
    docker compose up -d
    if [ $? -ne 0 ] ; then
        echo "💾 Up failed, retrying ... ⚠️"
        manual=1
        cleanup_stack
        manual=0
        docker compose up -d
        if [ $? -ne 0 ] ; then
            echo "💾 Up failed ❌"
            exit 1
        fi
    fi

    rm -rf init/plugins init/bunkerweb
    mkdir -p init/plugins init/bunkerweb
    docker compose -f docker-compose.init.yml up --build
    if [ $? -ne 0 ] ; then
        echo "💾 Build failed ❌"
        exit 1
    elif ! [[ -d "init/plugins/clamav" ]]; then
        echo "💾 ClamAV plugin not found ❌"
        exit 1
    elif ! [[ -d "init/bunkerweb/core" ]]; then
        echo "💾 BunkerWeb's core plugins directory not found ❌"
        exit 1
    elif ! [[ -d "init/bunkerweb/db" ]]; then
        echo "💾 BunkerWeb's database directory not found ❌"
        exit 1
    elif ! [[ -f "init/bunkerweb/settings.json" ]]; then
        echo "💾 BunkerWeb's settings file not found ❌"
        exit 1
    fi

    manual=1
    cleanup_stack
    manual=0

    docker compose -f docker-compose.test.yml build
    if [ $? -ne 0 ] ; then
        echo "💾 Build failed ❌"
        exit 1
    fi
else
    sudo rm -rf external bunkerweb bunkerweb-plugins
    echo "💾 Cloning BunkerWeb Plugins ..."
    git clone https://github.com/bunkerity/bunkerweb-plugins.git

    echo "💾 Extracting ClamAV plugin ..."
    mkdir external
    sudo cp -r bunkerweb-plugins/clamav external/clamav
    sudo cp -r external/clamav /etc/bunkerweb/plugins/clamav
    rm -rf bunkerweb-plugins

    echo "💾 Extracting settings.json file, db and core directory ..."
    mkdir bunkerweb
    sudo cp /usr/share/bunkerweb/settings.json bunkerweb/
    sudo cp -r /usr/share/bunkerweb/core bunkerweb/
    sudo cp -r /usr/share/bunkerweb/db bunkerweb/

    sudo chown -R nginx:nginx /etc/bunkerweb
    sudo chmod -R 777 /etc/bunkerweb/plugins external bunkerweb
fi

tests="local multisite"

if [ "$integration" == "docker" ] ; then
    tests="$tests mariadb mysql postgres"
fi

for test in $tests
do
    if [ "$integration" == "docker" ] ; then
        echo "💾 Creating the bw-docker network ..."
        docker network create bw-docker
    fi

    if [ "$test" = "local" ] ; then
        echo "💾 Running tests with a local database ..."
    elif [ "$test" = "multisite" ] ; then
        echo "💾 Running tests with MULTISITE set to yes and with multisite settings ..."
        if [ "$integration" == "docker" ] ; then
            find . -type f -name 'docker-compose.*' -exec sed -i 's@MULTISITE: "no"$@MULTISITE: "yes"@' {} \;
            sed -i '16i \      bwadm.example.com_SERVER_NAME: "bwadm.example.com"' docker-compose.yml
            sed -i "21i \      bwadm.example.com_CUSTOM_CONF_MODSEC_CRS_test_service_conf: 'SecRule REQUEST_FILENAME \"@rx ^/test\" \"id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog\"'" docker-compose.yml
            sed -i 's@USE_REVERSE_PROXY@bwadm.example.com_USE_REVERSE_PROXY@' docker-compose.yml
            sed -i 's@REVERSE_PROXY_HOST@bwadm.example.com_REVERSE_PROXY_HOST@' docker-compose.yml
            sed -i 's@REVERSE_PROXY_URL@bwadm.example.com_REVERSE_PROXY_URL@' docker-compose.yml
            sed -i '16i \      SERVICE_SERVER_NAME: "bwadm.example.com"' docker-compose.test.yml
            sed -i "21i \      CUSTOM_CONF_SERVICE_MODSEC_CRS_test_service_conf: 'SecRule REQUEST_FILENAME \"@rx ^/test\" \"id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog\"'" docker-compose.test.yml
            sed -i 's@GLOBAL_USE_REVERSE_PROXY@SERVICE_USE_REVERSE_PROXY@' docker-compose.test.yml
            sed -i 's@GLOBAL_REVERSE_PROXY_HOST@SERVICE_REVERSE_PROXY_HOST@' docker-compose.test.yml
            sed -i 's@GLOBAL_REVERSE_PROXY_URL@SERVICE_REVERSE_PROXY_URL@' docker-compose.test.yml
        else
            sudo sed -i 's@MULTISITE=.*$@MULTISITE=yes@' /etc/bunkerweb/variables.env
            echo "bwadm.example.com_SERVER_NAME=bwadm.example.com" | sudo tee -a /etc/bunkerweb/variables.env
            sudo mkdir -p /etc/bunkerweb/configs/modsec-crs/bwadm.example.com
            echo 'SecRule REQUEST_FILENAME "@rx ^/test" "id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog"' | sudo tee /etc/bunkerweb/configs/modsec-crs/bwadm.example.com/test_service_conf.conf
            sudo chown -R nginx:nginx /etc/bunkerweb
            sudo chmod 777 /etc/bunkerweb/configs/modsec-crs/bwadm.example.com/test_service_conf.conf
            sudo sed -i 's@USE_REVERSE_PROXY@bwadm.example.com_USE_REVERSE_PROXY@' /etc/bunkerweb/variables.env
            sudo sed -i 's@REVERSE_PROXY_HOST@bwadm.example.com_REVERSE_PROXY_HOST@' /etc/bunkerweb/variables.env
            sudo sed -i 's@REVERSE_PROXY_URL@bwadm.example.com_REVERSE_PROXY_URL@' /etc/bunkerweb/variables.env

            export GLOBAL_MULTISITE="yes"
            export CUSTOM_CONF_SERVICE_MODSEC_CRS_test_service_conf='SecRule REQUEST_FILENAME "@rx ^/test" "id:10001,ctl:ruleRemoveByTag=attack-generic,ctl:ruleRemoveByTag=attack-protocol,nolog"'
            export SERVICE_USE_REVERSE_PROXY=$GLOBAL_USE_REVERSE_PROXY
            export SERVICE_REVERSE_PROXY_HOST=$GLOBAL_REVERSE_PROXY_HOST
            export SERVICE_REVERSE_PROXY_URL=$GLOBAL_REVERSE_PROXY_URL
            export SERVICE_SERVER_NAME=$GLOBAL_SERVER_NAME
            unset GLOBAL_USE_REVERSE_PROXY
            unset GLOBAL_REVERSE_PROXY_HOST
            unset GLOBAL_REVERSE_PROXY_URL
        fi
    elif [ "$test" = "mariadb" ] ; then
        echo "💾 Running tests with MariaDB database ..."
        echo "ℹ️ Keeping the MULTISITE variable to yes and multisite settings ..."
        find . -type f -name 'docker-compose.*' -exec sed -i 's@DATABASE_URI: ".*"$@DATABASE_URI: "mariadb+pymysql://bunkerweb:secret\@bw-db:3306/db"@' {} \;

        echo "💾 Starting mariadb ..."
        docker compose -f docker-compose.mariadb.yml up -d
        if [ $? -ne 0 ] ; then
            echo "💾 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            manual=0
            docker compose -f docker-compose.mariadb.yml up -d
            if [ $? -ne 0 ] ; then
                echo "💾 Up failed ❌"
                exit 1
            fi
        fi
    elif [ "$test" = "mysql" ] ; then
        echo "💾 Running tests with MySQL database ..."
        echo "ℹ️ Keeping the MULTISITE variable to yes and multisite settings ..."
        find . -type f -name 'docker-compose.*' -exec sed -i 's@DATABASE_URI: ".*"$@DATABASE_URI: "mysql+pymysql://bunkerweb:secret\@bw-db:3306/db"@' {} \;

        echo "💾 Starting mysql ..."
        docker compose -f docker-compose.mysql.yml up -d
        if [ $? -ne 0 ] ; then
            echo "💾 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            manual=0
            docker compose -f docker-compose.mysql.yml up -d
            if [ $? -ne 0 ] ; then
                echo "💾 Up failed ❌"
                exit 1
            fi
        fi
    elif [ "$test" = "postgres" ] ; then
        echo "💾 Running tests with PostgreSQL database ..."
        echo "ℹ️ Keeping the MULTISITE variable to yes and multisite settings ..."
        find . -type f -name 'docker-compose.*' -exec sed -i 's@DATABASE_URI: ".*"$@DATABASE_URI: "postgresql://bunkerweb:secret\@bw-db:5432/db"@' {} \;

        echo "💾 Starting postgres ..."
        docker compose -f docker-compose.postgres.yml up -d
        if [ $? -ne 0 ] ; then
            echo "💾 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            manual=0
            docker compose -f docker-compose.postgres.yml up -d
            if [ $? -ne 0 ] ; then
                echo "💾 Up failed ❌"
                exit 1
            fi
        fi
    fi

    echo "💾 Starting stack ..."
    if [ "$integration" == "docker" ] ; then
        docker compose up -d
        if [ $? -ne 0 ] ; then
            echo "💾 Up failed, retrying ... ⚠️"
            manual=1
            cleanup_stack
            if [ "$test" = "mariadb" ] ; then
                docker compose -f docker-compose.mariadb.yml up -d
                if [ $? -ne 0 ] ; then
                    echo "💾 Up failed ❌"
                    exit 1
                fi
            elif [ "$test" = "mysql" ] ; then
                docker compose -f docker-compose.mysql.yml up -d
                if [ $? -ne 0 ] ; then
                    echo "💾 Up failed ❌"
                    exit 1
                fi
            elif [ "$test" = "postgres" ] ; then
                docker compose -f docker-compose.postgres.yml up -d
                if [ $? -ne 0 ] ; then
                    echo "💾 Up failed ❌"
                    exit 1
                fi
            fi
            manual=0
            docker compose up -d
            if [ $? -ne 0 ] ; then
                echo "💾 Up failed ❌"
                exit 1
            fi
        fi
    else
        sudo systemctl start bunkerweb
        if [ $? -ne 0 ] ; then
            echo "💾 Start failed ❌"
            exit 1
        fi
    fi

    # Check if stack is healthy
    echo "💾 Waiting for stack to be healthy ..."
    i=0
    if [ "$integration" == "docker" ] ; then
        while [ $i -lt 120 ] ; do
            containers=("db-bw-1" "db-bw-scheduler-1")
            healthy="true"
            for container in "${containers[@]}" ; do
                check="$(docker inspect --format "{{json .State.Health }}" $container | grep "healthy")"
                if [ "$check" = "" ] ; then
                    healthy="false"
                    break
                fi
            done
            if [ "$healthy" = "true" ] ; then
                echo "💾 Docker stack is healthy ✅"
                break
            fi
            sleep 1
            i=$((i+1))
        done
        if [ $i -ge 120 ] ; then
            docker compose logs
            echo "💾 Docker stack is not healthy ❌"
            echo "🛡️ Showing BunkerWeb and BunkerWeb Scheduler logs ..."
            docker compose logs bw bw-scheduler
            exit 1
        fi
    else
        healthy="false"
        retries=0
        while [[ $healthy = "false" && $retries -lt 5 ]] ; do
            while [ $i -lt 120 ] ; do
                if sudo grep -q "BunkerWeb is ready" "/var/log/bunkerweb/error.log" ; then
                    echo "💾 Linux stack is healthy ✅"
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
                echo "💾 Linux stack is not healthy ❌"
                exit 1
            fi

            if ! [ -z "$(sudo journalctl -u bunkerweb --no-pager | grep "SYSTEMCTL - ❌")" ] ; then
                echo "💾 ⚠ Linux stack got an issue, restarting ..."
                sudo journalctl --rotate
                sudo journalctl --vacuum-time=1s
                manual=1
                cleanup_stack
                manual=0
                sudo systemctl start bunkerweb
                retries=$((retries+1))
            else
                healthy="true"
            fi
        done
        if [ $retries -ge 5 ] ; then
            echo "💾 Linux stack could not be healthy ❌"
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
        echo "💾 Test \"$test\" failed ❌"
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
        echo "💾 Test \"$test\" succeeded ✅"
    fi

    manual=1
    cleanup_stack
    manual=0

    echo " "

    if [ "$integration" == "docker" ] ; then
        echo "💾 Removing bw-docker network ..."

        docker network rm bw-docker

        if [ $? -ne 0 ] ; then
            echo "💾 Network removal failed ❌"
            exit 1
        fi
    fi
done

end=1
echo "💾 Tests are done ! ✅"
