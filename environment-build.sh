#!/bin/bash
#created by slixperi . blog @ rmccarth.info
#automation steps derived from this guide: https://holdmybeersecurity.com/2018/04/30/tales-of-a-red-teamer-ub-2018

#this is the tye of server we are spinning up. this ami is Ubuntu Server 16.04 LTS (HVM) x86, SSD Volume Type
AMI="ami-08bc77a2c7eb2b1da"
#environment variables for our AWS access
ACCESS_KEY_ID=$1
SECRET_ACCESS_KEY=$2

#aws configure stores these creds in our local cache so we can call aws commands
aws configure set access_key_id $ACCESS_KEY_ID
aws configure set secret_access_key $SECRET_ACCESS_KEY

#first setup the VPC that will host both our EC2 servers
echo "building our VPC network and establishing public gateways"
#build our VPC and store the JSON response so we can have the vpc-id for subnetting
VPC=$(aws ec2 create-vpc --cidr-block 10.21.0.0/16 --query 'Vpc.VpcId' | cut -d "\"" -f 2)
aws ec2 modify-vpc-attribute --enable-dns-hostnames --vpc-id $VPC
GATEWAY=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' | cut -d "\"" -f 2)
sleep 20
aws ec2 attach-internet-gateway --internet-gateway-id $GATEWAY --vpc-id $VPC

echo "creating a route for public access"
ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC --query 'RouteTable.RouteTableId' | cut -d "\"" -f 2)
aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $GATEWAY


echo "creating a subnet for our hosts"
#generate our subnet for both our EC2 servers
SUBNET=$(aws ec2 create-subnet --cidr-block 10.21.1.0/24 --vpc-id $VPC --query 'Subnet.SubnetId'| cut -d "\"" -f 2)
#generate our security group configuration to apply to our teamserver EC2 build
echo "attaching our route table to our subnet"
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $SUBNET

C2_SECURITY_GROUP=$(aws ec2 create-security-group --description "security group for our C2 node" --group-name c2-server-sg --vpc-id $VPC \
--query 'GroupId' | cut -d "\"" -f 2)

echo "setting security group policies"
#the C2 nodes ssh port should not be publically accessible, change the CIDR range to your personal subnet, or the subnet of the team's server
#and SSH in from that box (jump box)
aws ec2 authorize-security-group-ingress --group-id $C2_SECURITY_GROUP --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $C2_SECURITY_GROUP --protocol tcp --port 80 --cidr 0.0.0.0/0
#the second rule allows for port 80 access from any location, this is important since we might want our webserver to serve a page
#to phish etc.
echo "generating key pairs"
#generate key pair and store public key in aws, private key locally
aws ec2 create-key-pair --key-name c2server --query 'KeyMaterial' --output text > c2-server.pem
chmod 600 c2-server.pem

echo "configuring C2 node"
#spin up the C2 node.
COMMAND_SERVER_SETUP=$(aws ec2 run-instances --image-id $AMI --count 1 --instance-type t2.micro \
--security-group-ids $C2_SECURITY_GROUP --key-name c2server \
--subnet-id $SUBNET --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=RedC2Server}]' --associate-public-ip-address \
--query 'Instances[0].InstanceId' | cut -d "\"" -f 2)

echo "creating security group for team server"
#generate our security group configuration to apply to our teamserver EC2 build
TEAM_SECURITY_GROUP=$(aws ec2 create-security-group --description "security group for our teamserver" \
--group-name teamserver-sg --vpc-id $VPC \
--query 'GroupId' | cut -d "\"" -f 2)

echo "setting security group policies"
aws ec2 authorize-security-group-ingress --group-id $TEAM_SECURITY_GROUP --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $TEAM_SECURITY_GROUP --protocol all --port 0-65535 --cidr 10.21.1.0/24
#the above allows ssh from any address so long as it has the private key, and the second rule
#permits traffic from any other server in the same subnet (perfect if our C2 node is in the same subnet, can fwd traffic to our team)

echo "generating key pairs"
#generate key pair and store public key in aws, private key locally
aws ec2 create-key-pair --key-name teamserver --query 'KeyMaterial' --output text > teamserver.pem
chmod 600 teamserver.pem

echo "configuring team server"
#spin up the teamserver node.
TEAM_SERVER_SETUP=$(aws ec2 run-instances --image-id $AMI --count 1 --instance-type t2.micro --security-group-ids $TEAM_SECURITY_GROUP --key-name teamserver \
--subnet-id $SUBNET --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=RedTeamServer}]' --associate-public-ip-address \
--query 'Instances[0].InstanceId' | cut -d "\"" -f 2)

echo "waiting for our servers to become available...please be patient"
#wait until both status lights are green on each instance before we query for the public dns address
aws ec2 wait instance-status-ok --instance-ids $TEAM_SERVER_SETUP
aws ec2 wait instance-status-ok --instance-ids $COMMAND_SERVER_SETUP

COMMAND_SERVER_DNS=$(aws ec2 describe-instances --instance-ids $COMMAND_SERVER_SETUP --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicDnsName')
TEAM_SERVER_DNS=$(aws ec2 describe-instances --instance-ids $TEAM_SERVER_SETUP --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicDnsName')

#format the dns addresses so they look nice on the cmd line
COMMAND_SERVER_DNS=$(echo $COMMAND_SERVER_DNS | cut -d "\"" -f 2)
TEAM_SERVER_DNS=$(echo $TEAM_SERVER_DNS | cut -d "\"" -f 2)
echo "---"
echo " "
echo "You can now SSH into your C2-node: ssh -i c2-server.pem ubuntu@$COMMAND_SERVER_DNS"
echo "You can now SSH into your TeamServer: ssh -i teamserver.pem ubuntu@$TEAM_SERVER_DNS"

# generate heredoc for our various files
cat << EOF > .htaccess
RewriteEngine On
RewriteCond %{REQUEST_URI} ^/(admin/get.php|login/process.php|news.php)/?$ [NC]
RewriteRule ^.*$ http://$TEAM_SERVER_DNS:5000%{REQUEST_URI} [P]
RewriteRule ^.*$ https://google.com/ [L,R=302]
EOF

chmod +x ansible.sh
./ansible.sh $TEAM_SERVER_DNS $COMMAND_SERVER_DNS
