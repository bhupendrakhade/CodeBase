import json
import boto3
import uuid
from botocore.exceptions import BotoCoreError, ClientError

dynamodb = boto3.resource("dynamodb")
ec2 = boto3.client("ec2")
table = dynamodb.Table("VPCRecords")


def create_vpc(event, context):
    try:
        body = json.loads(event["body"])
        cidr_block = body.get("cidr_block", "10.0.0.0/16")
        subnet_count = body.get("subnet_count", 2)

        # Create VPC
        vpc = ec2.create_vpc(CidrBlock=cidr_block)
        vpc_id = vpc["Vpc"]["VpcId"]

        ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsSupport={"Value": True})
        ec2.modify_vpc_attribute(VpcId=vpc_id, EnableDnsHostnames={"Value": True})

        # Create subnets
        subnets = []
        for i in range(subnet_count):
            subnet_cidr = f"10.0.{i}.0/24"
            subnet = ec2.create_subnet(VpcId=vpc_id, CidrBlock=subnet_cidr)
            subnets.append(subnet["Subnet"]["SubnetId"])

        # Store data in DynamoDB
        record_id = str(uuid.uuid4())
        table.put_item(
            Item={
                "id": record_id,
                "vpc_id": vpc_id,
                "subnets": subnets
            }
        )

        return {
            "statusCode": 201,
            "body": json.dumps({"message": "VPC created", "vpc_id": vpc_id, "subnets": subnets})
        }
    except (BotoCoreError, ClientError) as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def get_vpcs(event, context):
    try:
        response = table.scan()
        return {"statusCode": 200, "body": json.dumps(response["Items"])}
    except (BotoCoreError, ClientError) as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def authenticate(event, context):
    try:
        user_token = event["headers"].get("Authorization")
        cognito_client = boto3.client("cognito-idp")
        user_info = cognito_client.get_user(AccessToken=user_token)

        return {"statusCode": 200, "body": json.dumps({"message": "User authenticated", "user": user_info})}
    except (BotoCoreError, ClientError) as e:
        return {"statusCode": 401, "body": json.dumps({"error": "Unauthorized", "details": str(e)})}


def lambda_handler(event, context):
    route = event.get("resource")
    if route == "/create-vpc":
        return create_vpc(event, context)
    elif route == "/get-vpcs":
        return get_vpcs(event, context)
    elif route == "/authenticate":
        return authenticate(event, context)
    else:
        return {"statusCode": 404, "body": json.dumps({"error": "Route not found"})}
