#!/bin/bash
KEY_PATH=./pem
KEY_NAME=ec2_key

mkdir -p ${KEY_PATH}
ssh-keygen -N "" -f ${KEY_NAME}
mv ${KEY_NAME}* ${KEY_PATH}/
chmod 777 ${KEY_PATH}/${KEY_NAME}
