#!/bin/bash

set -x

# Get variables from config.sh and output.sh
source output.sh
source config.sh

# Remove certificates and bucket

ssh_flags=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null "

ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'aws s3 rm s3://snap-cli-cert --recursive'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'aws s3 rb s3://snap-cli-cert'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'aws s3 rm s3://snap-store-files --recursive'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'aws s3 rb s3://snap-store-files'

# Delete instances
aws ec2 terminate-instances --instance-ids $snapproxy_instance $snapcli_instance $snapproxyreg_instance --no-cli-pager --region $region

# Delete instance profiles and roles
aws iam remove-role-from-instance-profile --instance-profile-name snap-client --role-name S3-Role-RO
aws iam delete-instance-profile --instance-profile-name snap-client
aws iam remove-role-from-instance-profile --instance-profile-name snap-proxy --role-name S3-Role-RW
aws iam delete-instance-profile --instance-profile-name snap-proxy
aws iam detach-role-policy  --role-name S3-Role-RW --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam delete-role --role-name S3-Role-RW
aws iam detach-role-policy  --role-name S3-Role-RO --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam delete-role --role-name S3-Role-RO

# Delete RDS DB
aws rds delete-db-instance --db-instance-identifier $db_instance --skip-final-snapshot  --delete-automated-backups --region $region --no-cli-pager

# Remove temporary files
rm block.json
rm Role-Trust-Policy.json
rm output.sh
