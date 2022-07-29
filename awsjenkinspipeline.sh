#!/bin/bash
##################PARAMETERS####################
Region="us-east-1"
AvailabilityZone="us-east-1a"
KEYPAIR="MyNewKeyPair"
SUBNETID=$(aws ec2 describe-subnets --query "Subnets[?(State=='available' && AvailabilityZone=='$AvailabilityZone')].SubnetId" --output text)
VPCID="vpc-8d9346f0"
SG="ebs-SG"
InstanceTag="Instance-EBS"
##################################################



##CREATE VOLUME
aws ec2 create-volume \
    --volume-type ${VolumeType} \
    --size ${SizeGB} \
	--no-encrypted \
	--region ${Region} --availability-zone ${AvailabilityZone} 
VOLUME_ID=$(aws ec2 describe-volumes  --query "Volumes[].VolumeId" --out text)

##CREATE A KEY PAIR
aws ec2 create-key-pair --key-name ${KEYPAIR} --query 'KeyMaterial' --output text > ${KEYPAIR}.pem
sudo chmod 600 ${KEYPAIR}.pem

##CREATE A SG open from all IPs
aws ec2 create-security-group --region ${Region} --group-name ${SG} --description "EBS Security group"  --vpc-id ${VPCID}
SG_ID=$(aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='${SG}'].GroupId" --out text)
aws ec2 authorize-security-group-ingress --group-id ${SG_ID}  --protocol tcp --port 22 --cidr 0.0.0.0/0 --region ${Region}
aws ec2 authorize-security-group-ingress --group-id ${SG_ID}  --protocol tcp --port 8080 --cidr 0.0.0.0/0 --region ${Region}

##SPIN INSTANCE 2
aws ec2 run-instances \
--image-id $(aws ec2 describe-images --filters "Name=name,Values=ubuntu/images/hvm-ssd/*20.04-amd64-server-????????" --query "sort_by(Images, &CreationDate)[-1:].[ImageId]" --out text) \
--count 1 \
--instance-type t2.micro \
--associate-public-ip-address \
--key-name ${KEYPAIR} \
--security-group-ids ${SG_ID} \
--subnet-id ${SUBNETID} \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${InstanceTag}}]"   \
--region ${Region} --out text \
--user-data file://installjenkins.sh
INSTANCE_IP=$(aws ec2 describe-instances --query "Reservations[].Instances[?SubnetId=='${SUBNETID}'].PublicIpAddress" --out text)
INSTANCE_ID=$(aws ec2 describe-instances --query "Reservations[].Instances[?SubnetId=='${SUBNETID}'].InstanceId" --out text)
echo $INSTANCE_ID 
aws ec2 wait instance-running --instance-ids  ${INSTANCE_ID}
ssh-keyscan -t rsa -H ${INSTANCE_IP}  >> ~/.ssh/known_hosts



while [ "$(ssh -i ${KEYPAIR}.pem ubuntu@${INSTANCE_IP}   'dpkg -s jenkins | head -n 2| tail -n 1')" != "Status: install ok installed" ] ; do echo "Jenkins unavailable" ; done; echo "Jenkins installed"  

ssh -i ${KEYPAIR}.pem ubuntu@${INSTANCE_IP}   "paste /home/ubuntu/passjenkins"  


##INSTALL JENKINS
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt update
sudo apt install openjdk-8-jdk -y
sudo apt install jenkins -y

sudo systemctl start jenkins
sudo systemctl status jenkins
sudo cat /var/lib/jenkins/secrets/initialAdminPassword > /home/ubuntu/passjenkins
sudo systemctl enable jenkins

brew services start jenkins-lts
brew services restart jenkins-lts
##Attatch volume to instance
aws ec2 attach-volume \
	--volume-id ${VOLUME_ID} \
	--instance-id ${INSTANCE_ID} \
	--device /dev/sdf

##Format the FS in the instance and add it to the fstab

ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo cp /etc/fstab /etc/fstab.orig"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo mkfs.xfs -f /dev/xvdf"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo mkdir /data"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo mount /dev/xvdf /data"
UUID=$(ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo blkid | grep xvdf | sed 's|\"| |g' | awk '{print $3}'")
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "echo "UUID=${UUID}  /data  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo umount /data;sudo mount -a"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo reboot"
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo lsblk -f"




##CLEANUP
ssh -i ${KEYPAIR}.pem ec2-user@${INSTANCE_IP} "sudo umount /data"
aws ec2 detach-volume --volume-id ${VOLUME_ID} ;sleep 60
aws ec2 delete-volume --volume-id ${VOLUME_ID}
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
aws ec2 wait instance-terminated --instance-ids  ${INSTANCE_ID}
aws ec2 delete-security-group --group-id ${SG_ID}
aws ec2 delete-key-pair --key-name ${KEYPAIR}