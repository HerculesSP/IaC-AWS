#!/bin/bash

ip=$1
AWS_ACCESS_KEY_ID=$2 
AWS_SECRET_ACCESS_KEY=$3
AWS_SESSION_TOKEN=$4
BUCKET_NAME=$5
sudo apt update -y
sudo apt install -y npm

PID=$(lsof -t -i:80)

if [ -n "$PID" ]; then
    sudo kill -9 $(sudo lsof -t -i:80)
fi

git clone https://github.com/Black-Screenn/Black-Screen.git

cd Black-Screen/web-data-viz

npm install

sed -i "s|^DB_HOST=.*|DB_HOST=\"$ip\"|" .env.dev
sed -i "s|^APP_PORT=.*|APP_PORT=80|" .env.dev
sed -i "s|^DB_USER=.*|DB_USER='usuario'|" .env.dev
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD='senha123@'|" .env.dev
sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=\"$AWS_ACCESS_KEY_ID\"|" .env.dev
sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=\"$AWS_SECRET_ACCESS_KEY\"|" .env.dev
sed -i "s|^AWS_SESSION_TOKEN=.*|AWS_SESSION_TOKEN=\"$AWS_SESSION_TOKEN\"|" .env.dev
sed -i "s|^BUCKET_NAME=.*|BUCKET_NAME=\"$BUCKET_NAME\"|" .env.dev


sudo nohup npm start > output.log 2>&1 &
exit

