db_name=snapproxydb
db_instance_prefix=snapproxydbinstance
db_size=100
db_class=db.t3.small
db_user=snapproxyuser
db_password=snapproxypassword
security_group=sg-0eee5c84a4a6de690
region=sa-east-1
ami=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id --region $region --query 'Parameters[].Value' --output text)
instance_type=t3.large
keypair=fabiomirmar
subnet=subnet-57ed9f33
ssh_key="/home/$(whoami)/.ssh/id_rsa"

# Install store-admin snap and run 
# "store-admin export token" in a 
# computer with Internet and browser 
# access to obtain a token
STORE_ADMIN_TOKEN=<token>
