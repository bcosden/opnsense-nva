#!/bin/bash

# VARIABLES
rg="opn-2nic"
loc="eastus"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PINK="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"
NORMAL="\033[0;39m"

usessh=true
vmname="opnVM"
username="azureuser"
password="MyP@ssword123"
vmsize="Standard_D2S_v3"

# Allow RG to be set via shell var
if [[ $1 ]]; then
    rg=$1
fi

# create a resource group
echo -e "$WHITE$(date +"%T")$GREEN Creating Resource Group$CYAN" $rg"$GREEN in $CYAN"$loc"$WHITE"
az group create -n $rg -l $loc -o none

# create nva virtual network
echo -e "$WHITE$(date +"%T")$GREEN Creating Virtual Network hubVnet $WHITE"
az network vnet create --address-prefixes 10.1.0.0/16 -n hubVnet -g $rg --subnet-name RouteServerSubnet --subnet-prefixes 10.1.1.0/25 -o none

# create nva subnets
echo -e "$WHITE$(date +"%T")$GREEN Creating subnets $WHITE"
echo ".... creating external"
az network vnet subnet create -g $rg --vnet-name hubVnet -n external --address-prefixes 10.1.3.0/24 -o none
echo ".... creating nva"
az network vnet subnet create -g $rg --vnet-name hubVnet -n nva --address-prefixes 10.1.4.0/24 -o none
echo ".... creating GatewaySubnet"
az network vnet subnet create -g $rg --vnet-name hubVnet -n GatewaySubnet --address-prefixes 10.1.200.0/26 -o none
echo ".... creating AzureBastionSubnet"
az network vnet subnet create -g $rg --vnet-name hubVnet -n AzureBastionSubnet --address-prefixes 10.1.6.0/26 -o none

# accept offer to ensure can be deployed
az vm image terms accept --urn thefreebsdfoundation:freebsd-13_1:13_1-release:13.1.0 -o none

# create OPNVM
echo -e "$WHITE$(date +"%T")$GREEN Creating OPN VM $WHITE"
az network public-ip create -n $vmname"-pip" -g $rg --version IPv4 --sku Standard -o none --only-show-errors
az network nic create -g $rg --vnet-name hubVnet --subnet nva -n $vmname"IntNIC" --private-ip-address 10.1.4.10 --ip-forwarding true -o none
az network nic create -g $rg --vnet-name hubVnet --subnet external -n $vmname"ExtNIC" --public-ip-address $vmname"-pip" --private-ip-address 10.1.3.10 --ip-forwarding true -o none
if [ $usessh = "true" ]; then
    az vm create -n $vmname \
        -g $rg \
        --image thefreebsdfoundation:freebsd-13_1:13_1-release:13.1.0 \
        --size $vmsize \
        --nics $vmname"ExtNIC" $vmname"IntNIC" \
        --authentication-type ssh \
        --admin-username $username \
        --ssh-key-values @~/.ssh/id_rsa.pub \
        -o none \
        --only-show-errors
else
    az vm create -n $vmname \
        -g $rg \
        --image thefreebsdfoundation:freebsd-13_1:13_1-release:13.1.0 \
        --size $vmsize \
        --nics $vmname"ExtNIC" $vmname"IntNIC" \
        --admin-username $username \
        --admin-password $password \
        --ssh-key-values @~/.ssh/id_rsa.pub \
        -o none \
        --only-show-errors
fi

echo -e "$WHITE$(date +"%T")$GREEN Configuring OPNSense on NVA $WHITE"
# Must use waagent v1 for Linux on freebsd. v2 is not compatible.
az vm extension set -g $rg -n CustomScriptForLinux --publisher Microsoft.OSTCExtensions --vm-name $vmname \
    --settings '{"fileUris": ["https://raw.githubusercontent.com/bcosden/opnsense-nva/master/2nic/configure.sh"],"commandToExecute": "./configure.sh"}' \
    -o none

echo "OPNSense deployed. Give the VM about 5 - 10 minutes to finish configuration."
echo "Then go to https://"$(az vm show -g $rg -n $vmname --show-details --query "publicIps" -o tsv)
echo "default login:"
echo "username: root"
echo "password: opnsense"
echo "to finish configuration:"
echo "0. CHANGE YOUR PASSWORD!!!!"
echo "1. Add WAN Firewall rule to enable SSH"
echo "2. Add FRR plug-in for BGP support"
echo "3. Add peering to the RouteServer"
