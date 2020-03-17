#!/bin/bash

#TEAM_SERVER_DNS="ec2-204-236-251-118.compute-1.amazonaws.com ansible_user=ubuntu"
#COMMAND_SERVER_DNS="ec2-3-88-24-166.compute-1.amazonaws.com ansible_user=ubuntu"

############# /etc/ansible/hosts configuration ##############

# sudo echo "[teamserver]" >> /etc/ansible/hosts
# sudo echo "$TEAM_SERVER_DNS" >> /etc/ansible/hosts
# sudo echo "[c2]" >> /etc/ansible/hosts
# sudo echo "$COMMAND_SERVER_DNS" >> /etc/ansible/hosts

# if you are ok running this script as sudo, comment out the above 4 lines.
# if not, then append the following to your /etc/ansible/hosts file (without #'s):

#[teamserver]
#*TEAM SERVER DNS FROM ./environement-build.sh output*
#[c2]
#*COMMAND SERVER DNS FROM ./environment-build.sh output*

ansible all --become -m shell -a "apt update -y && apt upgrade -y"
ansible c2 --become -m copy -a "src=.htaccess dest=/var/www/html/.htaccess"
ansible c2 --become -m copy -a "src=apache2.conf dest=/etc/apache2/apache2.conf"
ansible c2 --become -m shell -a "apt install apache2 -y && a2enmod ssl rewrite proxy proxy_http && a2ensite default-ssl.conf && systemctl restart apache2 && systemctl enable apache2"

ansible teamserver --become -m shell -a "apt install git && mkdir install && cd install && git clone https://github.com/EmpireProject/Empire.git && cd Empire && echo -ne '\n' | ./setup/install.sh && pip install pefile"
