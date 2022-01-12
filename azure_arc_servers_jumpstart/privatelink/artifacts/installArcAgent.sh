#!/bin/sh

ARGUMENT_LIST=(
    "token"
    "location"
    "subscriptionId"
    "resourceGroup"
)

# Read options from argument list
OPTS=$(getopt --options '' --long "$(printf "%s:," "${ARGUMENT_LIST[@]}")" --name "$0" -- "$@")

if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi

eval set -- "$OPTS"

# Map options and their arguments into variables
while true; do
  case "$1" in
    --token)            token=$2;           shift 2 ;;
    --location)         location=$2;        shift 2 ;;
    --subscriptionId)   subscriptionId=$2;  shift 2 ;;
    --resourceGroup)    resourceGroup=$2;   shift 2 ;;
    --)                 shift;              break ;;
    *)                  break ;;
  esac
done

# Check for any missing required options
for i in "${ARGUMENT_LIST[@]}"
do
  if [ -z ${!i} ]
    then
      echo "Missing argument $i"
      exit 1
  fi
done

# Block Azure IMDS
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

sudo apt-get update

# Download the installation package
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh # 2>/dev/null

# Install the hybrid agent
bash ~/install_linux_azcmagent.sh # 2>/dev/null

# Run connect command
azcmagent connect \
    --access-token $token \
    --location $location \
    --subscription-id $subscriptionId \
    --resource-group $resourceGroup\
    --cloud "AzureCloud" \
    --tags "Project=jumpstart_arcbox"
