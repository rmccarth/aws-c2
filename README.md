# aws-c2
v1 of a script that stands up 2 EC2 instances in AWS cloud. The first is a C2 server which can be configured to forward traffic to the second EC2 instance (a team server). 

# Usage 
```bash
apt install ansible
```  
Run the script and provide it your aws_access_key as the first argument, and your secret_access_key as the second argument.

```bash
sudo ./environment-build.sh asasdfsafsf3q4243 789098760987asdfas
```
If you don't want to run the script as sudo you will have to update your /etc/ansible/hosts file to the following format:
```
[teamserver]
*TEAM SERVER DNS FROM ./environement-build.sh output*
[c2]
*COMMAND SERVER DNS FROM ./environment-build.sh output*

# Upcoming Release

The next version of the release will utilize Ansible to configure the C2 node and the team server with the Empire framework. 


Inspired by: https://holdmybeersecurity.com/2018/04/30/tales-of-a-red-teamer-ub-2018
