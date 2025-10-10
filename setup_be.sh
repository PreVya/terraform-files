#!/bin/bash
set -e

sudo apt update -y
sudo apt install -y git python3 python3-pip unzip curl 
sudo apt --fix-broken install -y

echo "Installling aws cli..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

S3_BUCKET="${S3_BUCKET}"
BASE_DIR="/home/ubuntu"

cd $BASE_DIR
mkdir -p backend
if [ ! -d "$BASE_DIR/backend/.git" ]; then
  echo "Cloning Flask backend..."
  git clone https://github.com/PreVya/flask-backend.git backend
fi

aws s3 cp s3://$S3_BUCKET/flask.env $BASE_DIR/backend/.env

cd $BASE_DIR/backend
pip3 install --ignore-installed -r requirements.txt --break-system-packages

nohup python3 app.py --host 0.0.0.0 --port 5000 > backend.log 2>&1 &