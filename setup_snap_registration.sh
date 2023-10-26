#!/bin/bash

set -x

# Get variables from config.sh and output.sh
source output.sh
source config.sh

ssh_flags=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null "

wait_for_ssh() {
    # $1 is ipaddr
    local max_ssh_attempts=10
    local ssh_attempt_sleep_time=10
    local ipaddr=$1

    # Start with a sleep so that it waits a bit in case of a reboot
    sleep $ssh_attempt_sleep_time

    # Loop until SSH is successful or max_attempts is reached
    for ((i = 1; i <= $max_ssh_attempts; i++)); do
        ssh $ssh_flags -i $ssh_key ubuntu@${ipaddr} exit
        if [ $? -eq 0 ]; then
            echo "SSH connection successful."
            break
        else
            echo "Attempt $i: SSH connection failed. Retrying in $ssh_attempt_sleep_time seconds..."
            sleep $ssh_attempt_sleep_time
        fi
    done

    if [ $i -gt $max_ssh_attempts ]; then
        echo "Max SSH connection attempts reached. Exiting."
    fi
}

# Install awscli
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
        'sudo apt update'
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
        'sudo apt install awscli -y'

# Instal store-admin and register
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'sudo snap install store-admin'
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	"STORE_ADMIN_TOKEN=$STORE_ADMIN_TOKEN store-admin register --offline https://snaps.canonical.internal"

# Due to a bug using snap-store proxy on AWS instances, need to use snap-proxy from latest/edge/fix-sn2164 for now
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'sudo snap-store-proxy fetch-snaps snap-store-proxy --channel=latest/edge/fix-sn2164'
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'cp /var/snap/snap-store-proxy/common/downloads/snap-store-proxy-* /home/ubuntu'

# Export desired snaps to be side loaded
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'store-admin export snaps jq htop aws-cli core core22 core18 core20 snapd --channel=stable --arch=amd64 --export-dir .'
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'aws s3 mb s3://snap-store-files'
ssh $ssh_flags -i $ssh_key $snapproxyreg_public_ip \
	'aws s3 cp /home/ubuntu/ s3://snap-store-files --recursive --exclude "*" --include "*.tar.gz"'
