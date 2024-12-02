#!/bin/bash
#1
apt-get update
apt-get remove docker docker-engine docker.io containerd runc -y

echo "\$nrconf{restart} = 'a'" >> /etc/needrestart/needrestart.conf

apt-get install ca-certificates curl gnupg lsb-release -y
#2
curl -fsSL http://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo apt-key add -
#3
sudo add-apt-repository -y "deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"
#4
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
#5
systemctl start docker
#6
apt-get -y install apt-transport-https ca-certificates curl software-properties-common -y
#7
sudo docker version
# install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#2
sudo chmod +x /usr/local/bin/docker-compose
#3
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
#4
docker-compose --version
#5
cp /usr/share/zoneinfo/Asia/Shanghai  /etc/localtime
date

