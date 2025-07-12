#!/bin/bash
# Quick customer deployment script
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./deploy-new-customer.sh <container-id> <hostname>"
    exit 1
fi

ID=$1
HOSTNAME=$2

pct clone 999 $ID --hostname $HOSTNAME
pct set $ID --memory 512 --cores 1
pct set $ID --net0 name=eth0,bridge=vmbr0,ip=192.168.1.$ID/24,gw=192.168.1.1
pct start $ID

echo "Customer container $ID deployed as $HOSTNAME"
echo "Add SSL: pct exec $ID -- /root/setup-ssl.sh domain.com"