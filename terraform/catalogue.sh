#!/bin/bash
APP_VERSION=$1
echo "app_version: $APP_VERSION" #printing version in shellscript
yum install python3.11-devel python3.11-pip -y
pip3.11 install ansible botocore boto3
cd /tmp
ansible-pull -U https://github.com/sivadevopsdaws74s/ansible-roboshop-roles-tf.git -e component=catalogue -e app_version=$APP_VERSION main.yaml
#here passing declared variable refer catalouge roles .