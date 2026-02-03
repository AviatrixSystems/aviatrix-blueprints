#!/bin/bash
sudo yum update -y
sudo yum install docker -y
sudo systemctl start docker
sudo systemctl enable docker
sudo docker run -d --restart unless-stopped -p 80:80 yeasy/simple-web 