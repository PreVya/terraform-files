#!/bin/bash
set -e  # Exit on any error

sudo apt update -y
sudo apt install -y git curl unzip python3 python3-pip nodejs npm
sudo apt --fix-broken install -y

# Install yarn globally
sudo npm install -g yarn

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

S3_BUCKET="${S3_BUCKET}"
BASE_DIR="/home/ubuntu"

cd $BASE_DIR
mkdir -p backend frontend

# Fetch the EC2 instance's public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "Public IP detected: $PUBLIC_IP"

# Clone backend
if [ ! -d "$BASE_DIR/backend/.git" ]; then
  echo "Cloning Flask backend..."
  git clone https://github.com/PreVya/flask-backend.git backend
fi

# Clone frontend
if [ ! -d "$BASE_DIR/frontend/.git" ]; then
  echo "Cloning Express frontend..."
  git clone https://github.com/PreVya/express-frontend.git frontend
fi

# Fetch backend env from S3
aws s3 cp s3://$S3_BUCKET/flask.env $BASE_DIR/backend/.env

# Dynamically create frontend env using the detected public IP
cat <<EOF > $BASE_DIR/frontend/.env
PORT=3000
BACKEND_URL=http://$PUBLIC_IP:5000
EOF

# Install backend dependencies
echo "Installing backend dependencies..."
cd $BASE_DIR/backend
pip install --ignore-installed -r requirements.txt --break-system-packages

# Start Flask backend
nohup python3 app.py --host 0.0.0.0 --port 5000 > backend.log 2>&1 &

# Install frontend dependencies
echo "Installing frontend dependencies..."
cd $BASE_DIR/frontend
yarn install

# Start Express frontend
nohup yarn start > frontend.log 2>&1 &

echo "✅ Deployment complete!"
echo "Flask Backend running at:  http://$PUBLIC_IP:5000"
echo "Express Frontend running at: http://$PUBLIC_IP:3000"
