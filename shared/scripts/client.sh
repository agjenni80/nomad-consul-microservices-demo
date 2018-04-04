#!/bin/bash

set -e

CONFIGDIR=/ops/shared/config

CONSULCONFIGDIR=/etc/consul.d
NOMADCONFIGDIR=/etc/nomad.d
HOME_DIR=ubuntu

# Wait for network
sleep 15

IP_ADDRESS=$(curl http://instance-data/latest/meta-data/local-ipv4)
DOCKER_BRIDGE_IP_ADDRESS=(`ifconfig docker0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`)
REGION=$1
CLUSTER_TAG_VALUE=$2
SERVER_IP=$3
VAULT_URL=$4

# Consul
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/consul_client.json
sed -i "s/CLUSTER_TAG_VALUE/$CLUSTER_TAG_VALUE/g" $CONFIGDIR/consul_upstart.conf
sed -i "s/REGION/$REGION/g" $CONFIGDIR/consul_upstart.conf
sudo cp $CONFIGDIR/consul_client.json $CONSULCONFIGDIR/consul.json
sudo cp $CONFIGDIR/consul_upstart.conf /etc/init/consul.conf

sudo service consul start
sleep 10
export CONSUL_HTTP_ADDR=$IP_ADDRESS:8500

# Nomad
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" $CONFIGDIR/nomad_client.hcl
sed -i "s@VAULT_URL@$VAULT_URL@g" $CONFIGDIR/nomad_client.hcl
sudo cp $CONFIGDIR/nomad_client.hcl $NOMADCONFIGDIR/nomad.hcl
sudo cp $CONFIGDIR/nomad_upstart.conf /etc/init/nomad.conf

sudo service nomad start
sleep 10
export NOMAD_ADDR=http://$IP_ADDRESS:4646

# Add hostname to /etc/hosts
echo "127.0.0.1 $(hostname)" | sudo tee --append /etc/hosts

# Add Docker bridge network IP to /etc/resolv.conf (at the top)
#echo "nameserver $DOCKER_BRIDGE_IP_ADDRESS" | sudo tee /etc/resolv.conf.new
echo "nameserver $IP_ADDRESS" | sudo tee /etc/resolv.conf.new
cat /etc/resolv.conf | sudo tee --append /etc/resolv.conf.new
sudo mv /etc/resolv.conf.new /etc/resolv.conf

# Add search service.consul at bottom of /etc/resolv.conf
echo "search service.consul" | sudo tee --append /etc/resolv.conf

# Set env vars for tool CLIs
echo "export VAULT_ADDR=$VAULT_URL" | sudo tee --append /home/$HOME_DIR/.bashrc
echo "export NOMAD_ADDR=http://$IP_ADDRESS:4646" | sudo tee --append /home/$HOME_DIR/.bashrc

# Install Java and queue-master.jar
sudo apt install -y default-jre
mkdir -p /home/ubuntu/jars
cp /ops/shared/jars/* /home/ubuntu/jars

# Move daemon.json to /etc/docker
sudo echo "{\"hosts\":[\"tcp://0.0.0.0:2375\",\"unix:///var/run/docker.sock\"],\"cluster-store\":\"consul://$IP_ADDRESS:8500\",\"cluster-advertise\":\"$IP_ADDRESS:2375\",\"dns\":[\"$IP_ADDRESS\"],\"dns-search\":[\"service.consul\"]}" > /home/ubuntu/daemon.json
sudo mkdir -p /etc/docker
sudo mv /home/ubuntu/daemon.json /etc/docker/daemon.json

# Start Docker
sudo service docker restart
