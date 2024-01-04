terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.30.0"
    }
    archive = {
      source = "hashicorp/archive"
      version = "2.4.1"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

provider "archive" {}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/s3_sqs_lambda"
}

data "archive_file" "function_source" {
  type = "zip"
  source_dir = "app"
  output_path = "archive/my_lambda_function.zip"
}

resource "aws_sqs_queue" "s3_sqs_lambda_dlq" {
  name = "s3_sqs_lambda_dlq"
}

resource "aws_sqs_queue" "s3_sqs_lambda" {
  name = "s3_sqs_lambda"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.s3_sqs_lambda_dlq.arn
    maxReceiveCount = 1
  })
}

resource "aws_s3_bucket" "bucket" {

  bucket = "s3-sqs-lambda-15632876-9dba-4a34-b2e8-cf83c6d1039b"

}

resource "aws_s3_bucket_notification" "bucket_notification" {

  bucket = aws_s3_bucket.bucket.id

  queue {
    queue_arn = aws_sqs_queue.s3_sqs_lambda.arn
    events = [
      "s3:ObjectCreated:*"
    ]
  }

}

data "aws_iam_policy_document" "ipd_s3_sqs" {

  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "s3.amazonaws.com"
      ]
    }
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      aws_sqs_queue.s3_sqs_lambda.arn
    ]
  }

}

resource "aws_sqs_queue_policy" "sqp" {
  queue_url = aws_sqs_queue.s3_sqs_lambda.id
  policy = data.aws_iam_policy_document.ipd_s3_sqs.json
}

data "aws_iam_policy_document" "assume" {

  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com"
      ]
    }
  }

}

resource "aws_iam_role" "role" {

  assume_role_policy = data.aws_iam_policy_document.assume.json

  name = "role_for_s3_sqs_lambda"

}

resource "aws_iam_role_policy_attachment" "rpa_lambda" {

  role = aws_iam_role.role.id

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

}

data "aws_iam_policy_document" "ipd_sqs" {
  
  statement {
    
    actions = [
      "sqs:DeleteMessage",
      "sqs:ReceiveMessage",
      "sqs:GetQueueAttributes"
    ]

    effect = "Allow"

    resources = [
      "${aws_sqs_queue.s3_sqs_lambda.arn}"
    ]

  }

}

resource "aws_iam_policy" "ip_sqs" {
  policy = data.aws_iam_policy_document.ipd_sqs.json
}

resource "aws_iam_role_policy_attachment" "rpa_sqs" {
  
  role = aws_iam_role.role.id
  
  policy_arn = aws_iam_policy.ip_sqs.arn

}

resource "aws_lambda_function" "function" {
  function_name = "s3_sqs_lambda"
  handler = "simple_lambda.lambda_handler"
  role = aws_iam_role.role.arn
  runtime = "python3.10"
  filename = data.archive_file.function_source.output_path
  source_code_hash = data.archive_file.function_source.output_base64sha256
  depends_on = [
    aws_iam_role_policy_attachment.rpa_lambda,
    aws_cloudwatch_log_group.lambda_log_group
    ]
  tags = {
    "Name" = "s3_sqs_lambda"
  }
}

resource "aws_lambda_event_source_mapping" "lesm" {
  
  function_name = aws_lambda_function.function.arn

  event_source_arn = aws_sqs_queue.s3_sqs_lambda.arn

}
