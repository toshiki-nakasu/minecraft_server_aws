#!/bin/bash
# ---------------------------------------------
# Params
# ---------------------------------------------
ENV_PATH=./.env
source $ENV_PATH
PEM_DIR=pem
SSH_KEY_PATH=./${PEM_DIR}/ec2_key
LOCAL_WORK_DIR=./minecraft
MAIN_DIR=data
BACKUP_DIR_NAME=backups
REMOTE_HOME_DIR=/home/ubuntu
REMOTE_WORK_PATH=${REMOTE_HOME_DIR}/${SERVER_NAME}
# BLUEMAP_CONF_PATH=${REMOTE_WORK_PATH}/data/plugins/BlueMap/core.conf


# ---------------------------------------------
# INIT Commands
# ---------------------------------------------
if [ "$1" = "init_local" ]; then
    if [ "$2" = "true" ]; then
        ./keygen.sh
    fi

    cd tf/
    terraform init
    terraform apply
    ./output_dump.sh
    cd ..
fi


if [ "$1" = "init_ec2" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} <<EOC
        mkdir -p ${REMOTE_WORK_PATH}
        mkdir -p ${REMOTE_WORK_PATH}/${BACKUP_DIR_NAME}
        mkdir -p ${REMOTE_WORK_PATH}/data
EOC

    scp -i ${SSH_KEY_PATH} ${ENV_PATH} ubuntu@${PUBLIC_IP}:${REMOTE_WORK_PATH}
    scp -i ${SSH_KEY_PATH} ${LOCAL_WORK_DIR}/* ubuntu@${PUBLIC_IP}:${REMOTE_WORK_PATH}

    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} <<EOC
        cd ${REMOTE_WORK_PATH}
        sudo docker compose --env-file $ENV_PATH up -d
EOC
fi


# ---------------------------------------------
# Local backup Commands
# ---------------------------------------------
if [ "$1" = "bak" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} docker exec -i ${BACKUP_CONTAINER_NAME} backup now

    mkdir -p ${LOCAL_WORK_DIR}/../${BACKUP_DIR_NAME}
    scp -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP}:${REMOTE_WORK_PATH}/${BACKUP_DIR_NAME}/* ${LOCAL_WORK_DIR}/../${BACKUP_DIR_NAME}/
fi

if [ "$1" = "restore" ]; then
    if [ "$2" = "" ]; then
        echo "no argument"
        exit 0
    fi

    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} <<EOC
        cd ${REMOTE_WORK_PATH}
        sudo docker compose down
        mkdir -p ${MAIN_DIR}_bak
        rm -rf ${MAIN_DIR}_bak

        sudo mv ${MAIN_DIR} ${MAIN_DIR}_bak
        mkdir ${MAIN_DIR}
        tar -xvzf ${BACKUP_DIR_NAME}/$2 -C ${MAIN_DIR}/
        sudo docker compose --env-file $ENV_PATH up -d
        cd ..
EOC
fi


# ---------------------------------------------
# General Commands
# ---------------------------------------------
if [ "$1" = "ssh" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP}
fi

if [ "$1" = "rcon" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} sudo docker exec -i ${SERVER_CONTAINER_NAME} rcon-cli
fi


# ---------------------------------------------
# No arg Commands
# ---------------------------------------------
if [ "$1" = "" ]; then
    echo "no argument"
fi

exit 0
