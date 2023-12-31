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

# Set the hostname
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo hostnamectl hostname snaps.canonical.internal'

# Generate the CA
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'openssl req -new -x509 -extensions v3_ca -keyout cakey.pem -out cacert.pem -days 3650 -subj "/C=BR/ST=Sao_Paulo/L=Sao_Paulo/O=Canonical/CN=snaps.canonical.internal" -passin 'pass:passw0rd' -passout 'pass:passw0rd''

# Generate the CSR
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'openssl genrsa -out server.key 2048'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'openssl req -new -key server.key -out server.csr -subj "/C=BR/ST=Sao_Paulo/L=Sao_Paulo/O=Canonical/CN=snaps.canonical.internal"'

# Sign the certificate and generate SAN
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
'cat <<EOF > v3.ext
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer:always
basicConstraints       = CA:TRUE
keyUsage               = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement, keyCertSign
subjectAltName         = DNS:snaps.canonical.internal, DNS:*.canonical.internal
issuerAltName          = issuer:copy
EOF'

ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'openssl x509 -req -days 365 -in server.csr -out server.crt -CA ./cacert.pem -CAkey ./cakey.pem -passin 'pass:passw0rd' -extfile v3.ext'

# Add CA certificate to trusted db
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip\
	'sudo cp cacert.pem /usr/local/share/ca-certificates/cacert.crt'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo update-ca-certificates'

# Install DB client
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo apt update -y && sudo apt install postgresql-client-common postgresql-client-14 -y'

# Create required DB extension
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
'cat <<EOF > proxydb.sql
CREATE EXTENSION "btree_gist";
EOF'

ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	"PGPASSWORD=$db_password psql -h $db_endpoint -U $db_user -d $db_name < proxydb.sql"

# Install awscli
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'sudo apt update'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
        'sudo apt install awscli -y'

# Download and install snap-store-proxy
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'aws s3 cp s3://snap-store-files/offline-snap-store.tar.gz .'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'tar xvzf offline-snap-store.tar.gz'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'cd offline-snap-store && sudo ./install.sh'

# Configure snap-store-proxy

ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo snap-proxy config proxy.domain="snaps.canonical.internal"'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	"sudo snap-proxy config proxy.db.connection="postgresql://$db_user:$db_password@$db_endpoint:5432/$db_name""
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'snap-proxy check-connections'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo snap-store-proxy enable-airgap-mode'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'snap-proxy status'

# Configure Certificates
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'cat server.crt server.key | sudo snap-proxy import-certificate'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo snap restart snap-store-proxy'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'snap-proxy status'

# Copy certificates to S3 bucket so client can use
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'aws s3 mb s3://snap-cli-cert'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'aws s3 cp cacert.pem s3://snap-cli-cert/cacert.crt'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'aws s3 cp server.crt s3://snap-cli-cert/server.crt'

# Side load snaps to the store
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo aws s3 cp s3://snap-store-files/ /var/snap/snap-store-proxy/common/snaps-to-push/ --recursive --exclude "offline-snap-store.tar.gz"'
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'for snap in `ls /var/snap/snap-store-proxy/common/snaps-to-push/`; do sudo snap-store-proxy push-snap /var/snap/snap-store-proxy/common/snaps-to-push/$snap --push-channel-map; done'

# Due to a bug using snap-store proxy on AWS instances, need to use snap-proxy from latest/edge/fix-sn2164 for now
ssh $ssh_flags -i $ssh_key $snapproxy_public_ip \
	'sudo snap refresh snap-store-proxy --channel=latest/edge/fix-sn2164'

store_id=$(ssh $ssh_flags -i $ssh_key $snapproxy_public_ip "snap-proxy status | grep 'Store ID'")
echo "store_id=$(echo $store_id | awk '{print $3}')" | tee -a output.sh
