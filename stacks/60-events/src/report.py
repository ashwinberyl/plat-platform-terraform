"""plat-report: runs on a schedule, counts jobs by status and publishes the summary to SNS."""
import os
from collections import Counter

import boto3

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
SNS = boto3.client("sns")


def handler(event, context):
    counts, kwargs = Counter(), {"ProjectionExpression": "#s", "ExpressionAttributeNames": {"#s": "status"}}
    while True:
        page = TABLE.scan(**kwargs)
        counts.update(item["status"] for item in page["Items"])
        if "LastEvaluatedKey" not in page:
            break
        kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    lines = [f"{status}: {n}" for status, n in sorted(counts.items())] or ["no jobs"]
    SNS.publish(TopicArn=os.environ["TOPIC_ARN"], Subject="plat nightly report", Message="\n".join(lines))
    return dict(counts)
