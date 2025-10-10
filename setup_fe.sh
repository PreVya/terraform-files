#!/bin/bash
set -e

sudo apt update -y
sudo apt install -y git curl unzip nodejs npm
sudo apt --fix-broken install -y
sudo npm install -g yarn

BACKEND_IP="${BACKEND_IP}"
BASE_DIR="/home/ubuntu"
cd $BASE_DIR
mkdir -p frontend

if [ ! -d "$BASE_DIR/frontend/.git" ]; then
  echo "Cloning Express frontend..."
  git clone https://github.com/PreVya/express-frontend.git frontend
fi

cat <<EOF > $BASE_DIR/frontend/.env
PORT=3000
BACKEND_URL=http://$BACKEND_IP:5000
EOF

cd $BASE_DIR/frontend
yarn install
nohup yarn start > frontend.log 2>&1 &