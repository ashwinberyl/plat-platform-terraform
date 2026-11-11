"""plat-ingest: SQS -> DynamoDB.

S3 announces each new object under raw/ to the queue. For every announcement this function reads the
object, counts its rows and records a job item in plat-jobs. Any record that fails is reported back
individually, so the rest of the batch is not retried.
"""
import json
import os
import time
import urllib.parse

import boto3

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
S3 = boto3.client("s3")
TTL_DAYS = int(os.environ.get("TTL_DAYS", "30"))


def handle_s3_record(rec):
    bucket = rec["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(rec["s3"]["object"]["key"])
    body = S3.get_object(Bucket=bucket, Key=key, Range="bytes=0-1048575")["Body"].read().decode("utf-8", "replace")
    if "POISON" in body:  # lets you rehearse the dead-letter queue on purpose
        raise ValueError(f"poison message in {key}")
    now = int(time.time())
    TABLE.put_item(Item={
        "job_id": key,
        "status": "INGESTED",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "rows": max(len(body.splitlines()) - 1, 0),
        "expires_at": now + TTL_DAYS * 86400,
    })


def handler(event, context):
    failures = []
    for message in event["Records"]:
        try:
            for rec in json.loads(message["body"]).get("Records", []):  # s3:TestEvent has no Records
                handle_s3_record(rec)
        except Exception as exc:  # noqa: BLE001
            print(f"failed {message['messageId']}: {exc}")
            failures.append({"itemIdentifier": message["messageId"]})
    return {"batchItemFailures": failures}
