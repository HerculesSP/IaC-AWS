#!/bin/bash
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y ca-certificates curl > /dev/null 2>&1
sudo install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc > /dev/null 2>&1
sudo chmod a+r /etc/apt/keyrings/docker.asc > /dev/null 2>&1

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null 2>&1

sudo apt-get update -y > /dev/null 2>&1

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

sudo groupadd docker > /dev/null 2>&1 || true
sudo usermod -aG docker $USER > /dev/null 2>&1
newgrp docker > /dev/null 2>&1
