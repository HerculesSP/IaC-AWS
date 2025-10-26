#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

docker pull mysql:latest

CONTAINER_NAME="banco"

if [ ! "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker run --name $CONTAINER_NAME -e MYSQL_ROOT_PASSWORD=rootpassword -d mysql:latest
    sleep 20
    docker exec -i $CONTAINER_NAME mysql -uroot -prootpassword < /caminho/para/seu/arquivo.sql

fi


