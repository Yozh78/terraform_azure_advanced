#!/bin/bash
sudo apt update -y
sudo apt-get install -y \
	ca-certificates \
	curl \
	gnupg \
	lsb-release
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt-get install -y git-all
git clone https://github.com/lewagon/devsecops-guest-app && cd ./devsecops-guest-app && git checkout docker
sudo docker compose up
