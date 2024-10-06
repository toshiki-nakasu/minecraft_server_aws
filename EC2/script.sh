#!/bin/bash
ENV_PATH=./.env
source $ENV_PATH
SSH_KEY_PATH=./pem/ec2_key
LOCAL_WORK_DIR=./minecraft
REMOTE_HOME_DIR=/home/ubuntu
REMOTE_WORK_PATH=${REMOTE_HOME_DIR}/${SERVER_NAME}

if [ "$1" = "init" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} <<EOC
        mkdir -p ${REMOTE_WORK_PATH}
        mkdir -p ${REMOTE_WORK_PATH}/backups
        mkdir -p ${REMOTE_WORK_PATH}/data
EOC

    scp -i ${SSH_KEY_PATH} ${ENV_PATH} ubuntu@${PUBLIC_IP}:${REMOTE_WORK_PATH}
    scp -i ${SSH_KEY_PATH} ${LOCAL_WORK_DIR}/* ubuntu@${PUBLIC_IP}:${REMOTE_WORK_PATH}

    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} <<EOC
        cd ${REMOTE_WORK_PATH}
        sudo docker compose --env-file $ENV_PATH up -d
EOC
fi

if [ "$1" = "exec" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP}
fi

if [ "$1" = "rcon" ]; then
    ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no ubuntu@${PUBLIC_IP} sudo docker exec -i ${SERVER_CONTAINER_NAME} rcon-cli
fi

if [ "$1" = "" ]; then
    echo "no argument"
fi

exit 0
