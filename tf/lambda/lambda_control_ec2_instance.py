import boto3
import os
import logging

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

region = os.environ['REGION']
instances = [os.environ['INSTANCE_ID']]
host_name = os.environ['HOST_NAME']
hosted_zone_id = os.environ['HOSTED_ZONE_ID']
server_container_name = os.environ['SERVER_CONTAINER_NAME']
backup_container_name = os.environ['BACKUP_CONTAINER_NAME']

ec2_client = boto3.client("ec2", region_name=region)
route53_client = boto3.client('route53', region_name=region)
ssm_client = boto3.client('ssm', region_name=region)


def lambda_handler(event, context):
    action = event["Action"]
    response = ec2_client.describe_instances(InstanceIds=instances)
    ec2_status = response['Reservations'][0]['Instances'][0]['State']['Name']
    tags = response['Reservations'][0]['Instances'][0]['Tags']
    autoStop = next(t["Value"] for t in tags if t["Key"] == "AutoStop")
    LOGGER.info(f'{str(instances[0])} instance is {ec2_status} now.')

    if action == "Start":
        response = ec2_client.start_instances(InstanceIds=instances)
        instanceIDs = [response['StartingInstances'][0]['InstanceId']]

        # インスタンスが起動するまで待つ
        waiter = ec2_client.get_waiter('instance_running')
        waiter.wait(
            InstanceIds = instanceIDs,
            WaiterConfig = {'Delay': 5, 'MaxAttempts': 2}
        )

        ipaddress = ec2_client.describe_instances(InstanceIds=instanceIDs)['Reservations'][0]['Instances'][0]['PublicIpAddress']
        add_dns_record(instance_ip=ipaddress)
        LOGGER.info(f'started your instance: {str(instances[0])}')

    elif action == "Stop" and autoStop == "true":
        # commands = [f"sudo docker exec -i {server_container_name} rcon-cli say test", "sleep 3m", f"docker exec -i {backup_container_name} backup now"]
        # ssm_client.send_command(InstanceIds=instances, DocumentName="AWS-RunShellScript", Parameters={"commands": commands})

        response = ec2_client.stop_instances(InstanceIds=instances)
        instanceIDs = [response['StoppingInstances'][0]['InstanceId']]

        ipaddress = ec2_client.describe_instances(InstanceIds=instanceIDs)['Reservations'][0]['Instances'][0]['PublicIpAddress']
        remove_dns_record(instance_ip=ipaddress)
        LOGGER.info(f'stopped your instance: {str(instances[0])}')

    else:
        LOGGER.info('Lamdba function could not be executed.')


def add_dns_record(instance_ip=None,):
    dns_payload = set_dns_record(instance_ip, 'UPSERT')
    route53_client.change_resource_record_sets(HostedZoneId=hosted_zone_id, ChangeBatch=dns_payload)
    LOGGER.info(f"Added A record for {host_name} to {instance_ip}")


def remove_dns_record(instance_ip=None,):
    dns_payload = set_dns_record(instance_ip, 'DELETE')
    route53_client.change_resource_record_sets(HostedZoneId=hosted_zone_id, ChangeBatch=dns_payload)
    LOGGER.info(f"Removed A record from {host_name} to {instance_ip}")


def set_dns_record(instance_ip=None, action=str):
    dns_changes = {
        'Changes': [
            {
                'Action': action,
                'ResourceRecordSet': {
                    'Name': f"{host_name}.",
                    'Type': 'A',
                    'ResourceRecords': [
                        {
                            'Value': instance_ip
                        }
                    ],
                    'TTL': 300
                }
            }
        ]
    }

    return dns_changes
