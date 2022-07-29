#!/bin/bash
sudo wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt update
sudo apt install openjdk-8-jdk -y
sudo apt install jenkins -y
#sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins > /home/ubuntu/jenkinstatus
sudo cat /var/lib/jenkins/secrets/initialAdminPassword > /home/ubuntu/passjenkins
sudo apt install texlive-latex-base -y
