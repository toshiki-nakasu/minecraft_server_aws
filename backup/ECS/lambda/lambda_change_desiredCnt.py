import boto3
from botocore.exceptions import ClientError
import os
import json

def change_desiredCnt(cnt):
    retObj = {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({
            "Result ": "Success"
        })
    }

    try:
        client = boto3.client('ecs')
        service_update_result = client.update_service(
            cluster = os.environ.get('cluster'),
            service = os.environ.get('service'),
            desiredCount = cnt
        )
        print(service_update_result)

    except ClientError as e:
        print("exceptin: %s" % e)
        retObj = {
            "statusCode": 1000,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "Result ": "Failed"
            })
        }

    return retObj


def stop_service_task(event, context):
    return change_desiredCnt(0);


def start_service_task(event, context):
    return change_desiredCnt(1);
