#!/bin/bash

# Source the utils helper script
source /usr/share/bunkerweb/helpers/utils.sh

# Set the PYTHONPATH
export PYTHONPATH=/usr/share/bunkerweb/deps/python/

# Display usage information
function display_help() {
    echo "Usage: $(basename "$0") [start|stop|reload]"
    echo "Options:"
    echo "  start:   Create configurations and run necessary jobs for the bunkerweb service."
    echo "  stop:    Stop the bunkerweb service."
    echo "  reload:  Reload the bunkerweb service."
}

function stop_nginx() {
    pgrep nginx > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        log "SYSTEMCTL" "ℹ️ " "Stopping nginx..."
        nginx -s stop
        if [ $? -ne 0 ] ; then
            log "SYSTEMCTL" "❌" "Error while sending stop signal to nginx"
            log "SYSTEMCTL" "ℹ️ " "Stopping nginx (force)..."
            kill -TERM $(cat /var/run/bunkerweb/nginx.pid)
            if [ $? -ne 0 ] ; then
                log "SYSTEMCTL" "❌" "Error while sending term signal to nginx"
            fi
        fi
    fi
    count=0
    while [ 1 ] ; do
        pgrep nginx > /dev/null 2>&1
        if [ $? -ne 0 ] ; then
            break
        fi
        log "SYSTEMCTL" "ℹ️ " "Waiting for nginx to stop..."
        sleep 1
        count=$(($count + 1))
        if [ $count -ge 20 ] ; then
            break
        fi
    done
    if [ $count -ge 20 ] ; then
        log "SYSTEMCTL" "❌" "Timeout while waiting nginx to stop"
        exit 1
    fi
    log "SYSTEMCTL" "ℹ️ " "nginx is stopped"
}

function stop_scheduler() {
    if [ -f "/var/run/bunkerweb/scheduler.pid" ] ; then
        scheduler_pid=$(cat "/var/run/bunkerweb/scheduler.pid")
        log "SYSTEMCTL" "ℹ️ " "Stopping scheduler..."
        kill -SIGINT "$scheduler_pid"
        if [ $? -ne 0 ] ; then
            log "SYSTEMCTL" "❌" "Error while sending stop signal to scheduler"
            exit 1
        fi
    else
        log "SYSTEMCTL" "ℹ️ " "Scheduler already stopped"
        return 0
    fi
    count=0
    while [ -f "/var/run/bunkerweb/scheduler.pid" ] ; do
        sleep 1
        count=$(($count + 1))
        if [ $count -ge 10 ] ; then
            break
        fi
    done
    if [ $count -ge 10 ] ; then
        log "SYSTEMCTL" "❌" "Timeout while waiting scheduler to stop"
        exit 1
    fi
    log "SYSTEMCTL" "ℹ️ " "Scheduler is stopped"
}

# Start the bunkerweb service
function start() {

    # Set the PYTHONPATH
    export PYTHONPATH=/usr/share/bunkerweb/deps/python

    log "SYSTEMCTL" "ℹ️" "Starting BunkerWeb service ..."

    echo "nginx ALL=(ALL) NOPASSWD: /usr/sbin/nginx" > /etc/sudoers.d/bunkerweb
    chown -R nginx:nginx /etc/nginx

    # Create dummy variables.env
    if [ ! -f /etc/bunkerweb/variables.env ]; then
        sudo -E -u nginx -g nginx /bin/bash -c "echo -ne '# remove IS_LOADING=yes when your config is ready\nIS_LOADING=yes\nUSE_BUNKERNET=no\nDNS_RESOLVERS=8.8.8.8 8.8.4.4\nHTTP_PORT=80\nHTTPS_PORT=443\nAPI_LISTEN_IP=127.0.0.1\nSERVER_NAME=\n' > /etc/bunkerweb/variables.env"
        log "SYSTEMCTL" "ℹ️" "Created dummy variables.env file"
    fi

    # Stop scheduler if it's running
    stop_scheduler

    # Stop nginx if it's running
    stop_nginx

    # Generate temp conf for jobs and start nginx
    API_HTTP_PORT="$(grep "^API_HTTP_PORT=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$API_HTTP_PORT" = "" ] ; then
        API_HTTP_PORT="5000"
    fi
    API_SERVER_NAME="$(grep "^API_SERVER_NAME=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$API_SERVER_NAME" = "" ] ; then
        API_SERVER_NAME="bwapi"
    fi
    API_WHITELIST_IP="$(grep "^API_WHITELIST_IP=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$API_WHITELIST_IP" = "" ] ; then
        API_WHITELIST_IP="127.0.0.0/8"
    fi
    USE_REAL_IP="$(grep "^USE_REAL_IP=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$USE_REAL_IP" = "" ] ; then
        USE_REAL_IP="no"
    fi
    USE_PROXY_PROTOCOL="$(grep "^USE_PROXY_PROTOCOL=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$USE_PROXY_PROTOCOL" = "" ] ; then
        USE_PROXY_PROTOCOL="no"
    fi
    REAL_IP_FROM="$(grep "^REAL_IP_FROM=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$REAL_IP_FROM" = "" ] ; then
        REAL_IP_FROM="192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"
    fi
    REAL_IP_HEADER="$(grep "^REAL_IP_HEADER=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$REAL_IP_HEADER" = "" ] ; then
        REAL_IP_HEADER="X-Forwarded-For"
    fi
    HTTP_PORT="$(grep "^HTTP_PORT=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$HTTP_PORT" = "" ] ; then
        HTTP_PORT="8080"
    fi
    HTTPS_PORT="$(grep "^HTTPS_PORT=" /etc/bunkerweb/variables.env | cut -d '=' -f 2)"
    if [ "$HTTPS_PORT" = "" ] ; then
        HTTPS_PORT="8443"
    fi
    sudo -E -u nginx -g nginx /bin/bash -c "echo -ne 'IS_LOADING=yes\nUSE_BUNKERNET=no\nSERVER_NAME=\nAPI_HTTP_PORT=${API_HTTP_PORT}\nAPI_SERVER_NAME=${API_SERVER_NAME}\nAPI_WHITELIST_IP=${API_WHITELIST_IP}\nUSE_REAL_IP=${USE_REAL_IP}\nUSE_PROXY_PROTOCOL=${USE_PROXY_PROTOCOL}\nREAL_IP_FROM=${REAL_IP_FROM}\nREAL_IP_HEADER=${REAL_IP_HEADER}\nHTTP_PORT=${HTTP_PORT}\nHTTPS_PORT=${HTTPS_PORT}\n' > /var/tmp/bunkerweb/tmp.env"
    sudo -E -u nginx -g nginx /bin/bash -c "PYTHONPATH=/usr/share/bunkerweb/deps/python/ /usr/share/bunkerweb/gen/main.py --variables /var/tmp/bunkerweb/tmp.env --no-linux-reload"
    if [ $? -ne 0 ] ; then
        log "SYSTEMCTL" "❌" "Error while generating config from /var/tmp/bunkerweb/tmp.env"
        exit 1
    fi

    # Start nginx
    log "SYSTEMCTL" "ℹ️" "Starting temp nginx ..."
    nginx -e /var/log/bunkerweb/error.log
    if [ $? -ne 0 ] ; then
        log "SYSTEMCTL" "❌" "Error while executing temp nginx"
        exit 1
    fi
    count=0
    while [ $count -lt 10 ] ; do
        check="$(curl -s -H "Host: healthcheck.bunkerweb.io" http://127.0.0.1:6000/healthz 2>&1)"
        if [ $? -eq 0 ] && [ "$check" = "ok" ] ; then
            break
        fi
        count=$(($count + 1))
        sleep 1
        log "SYSTEMCTL" "ℹ️" "Waiting for nginx to start ..."
    done
    if [ $count -ge 10 ] ; then
        log "SYSTEMCTL" "❌" "nginx is not started"
        exit 1
    fi
    log "SYSTEMCTL" "ℹ️" "nginx started ..."

    # Execute scheduler
    log "SYSTEMCTL" "ℹ️ " "Executing scheduler ..."
    sudo -E -u nginx -g nginx /bin/bash -c "PYTHONPATH=/usr/share/bunkerweb/deps/python/ /usr/share/bunkerweb/scheduler/main.py --variables /etc/bunkerweb/variables.env"
    if [ "$?" -ne 0 ] ; then
        log "SYSTEMCTL" "❌" "Scheduler failed"
        exit 1
    fi
    log "SYSTEMCTL" "ℹ️ " "Scheduler stopped"
}

function stop() {
    log "SYSTEMCTL" "ℹ️" "Stopping BunkerWeb service ..."

    stop_nginx
    stop_scheduler

    log "SYSTEMCTL" "ℹ️" "BunkerWeb service stopped"
}

function reload()
{

    log "SYSTEMCTL" "ℹ️" "Reloading BunkerWeb service ..."

    PID_FILE_PATH="/var/run/bunkerweb/scheduler.pid"
    if [ -f "$PID_FILE_PATH" ];
    then
        var=$(cat "$PID_FILE_PATH")
        # Send signal to scheduler to reload
        log "SYSTEMCTL" "ℹ️" "Sending reload signal to scheduler ..."
        kill -SIGHUP $var
        result=$?
        if [ $result -ne 0 ] ; then
            log "SYSTEMCTL" "❌" "Your command exited with non-zero status $result"
            exit 1
        fi
    else
        log "SYSTEMCTL" "❌" "Scheduler is not running"
        exit 1
    fi

    log "SYSTEMCTL" "ℹ️" "BunkerWeb service reloaded ..."
}

# List of differents args
case $1 in
    "start") 
    start
    ;;
    "stop") 
    stop
    ;;
    "reload") 
    reload
    ;;
    *)
    echo "Invalid option!"
    echo "List of options availables:"
    display_help
esac
