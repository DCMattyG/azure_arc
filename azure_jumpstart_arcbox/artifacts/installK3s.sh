#!/bin/bash
exec >installK3s.log
exec 2>&1

ARGUMENT_LIST=(
    "USER_NAME"
    "VM_NAME"
    "LOCATION"
    "STAGING_STORAGE"
    "SPN_CLIENT_ID"
    "SPN_CLIENT_SECRET"
    "SPN_TENANT_ID"
    "WORKSPACE"
)

# Read options from argument list
OPTS=$(getopt --options '' --long "$(printf "%s:," "${ARGUMENT_LIST[@]}")" --name "$0" -- "$@")

if [ $? != 0 ] ; then echo "Failed to parse options...exiting." >&2 ; exit 1 ; fi

eval set -- "$OPTS"

# Map options and their arguments into variables
while true; do
  case "$1" in
    --USER_NAME)          USER_NAME=$2;           shift 2 ;;
    --VM_NAME)            VM_NAME=$2;             shift 2 ;;
    --LOCATION)           LOCATION=$2;            shift 2 ;;
    --STAGING_STORAGE)    STAGING_STORAGE=$2;     shift 2 ;;
    --SPN_CLIENT_ID)      SPN_CLIENT_ID=$2;       shift 2 ;;
    --SPN_CLIENT_SECRET)  SPN_CLIENT_SECRET=$2;   shift 2 ;;
    --SPN_TENANT_ID)      SPN_TENANT_ID=$2;       shift 2 ;;
    --WORKSPACE)          WORKSPACE=$2;           shift 2 ;;
    --)                   shift;                  break ;;
    *)                    break ;;
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

sudo apt-get update

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
sudo adduser staginguser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
sudo echo "staginguser:ArcPassw0rd" | sudo chpasswd

publicIp=$(curl icanhazip.com)

# Installing Rancher K3s single master cluster using k3sup
sudo -u $USER_NAME mkdir /home/${USER_NAME}/.kube
curl -sLS https://get.k3sup.dev | sh
sudo cp k3sup /usr/local/bin/k3sup
sudo k3sup install --local --context arcbox-k3s --ip $publicIp --k3s-extra-args '--no-deploy traefik'
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
sudo cp kubeconfig /home/${USER_NAME}/.kube/config
sudo cp kubeconfig /home/${USER_NAME}/.kube/config.staging
sudo chown -R $USER_NAME /home/${USER_NAME}/.kube/
sudo chown -R staginguser /home/${USER_NAME}/.kube/config.staging

# Installing Helm 3
sudo snap install helm --channel=3.6/stable --classic # pinning 3.6 due to breaking changes in aak8s onboarding with 3.7

# Installing Azure CLI & Azure Arc Extensions
sudo apt-get update
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

sudo -u $USER_NAME az extension add --name connectedk8s
sudo -u $USER_NAME az extension add --name k8s-configuration
sudo -u $USER_NAME az extension add --name k8s-extension

sudo -u $USER_NAME az login --service-principal --username $SPN_CLIENT_ID --password $SPN_CLIENT_SECRET --tenant $SPN_TENANT_ID

# Onboard the cluster to Azure Arc and enabling Container Insights using Kubernetes extension
resourceGroup=$(sudo -u $USER_NAME az resource list --query "[?name=='$STAGING_STORAGE']".[resourceGroup] --resource-type "Microsoft.Storage/storageAccounts" -o tsv)
workspaceResourceId=$(sudo -u $USER_NAME az resource show --resource-group $resourceGroup --name $WORKSPACE --resource-type "Microsoft.OperationalInsights/workspaces" --query id -o tsv)
sudo -u $USER_NAME az connectedk8s connect --name $VM_NAME --resource-group $resourceGroup --location $LOCATION --tags 'Project=jumpstart_arcbox'
sudo -u $USER_NAME az k8s-extension create -n "azuremonitor-containers" --cluster-name ArcBox-K3s --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceResourceId

sudo service sshd restart

# Copying Rancher K3s kubeconfig file to staging storage account
sudo -u $USER_NAME az extension add --upgrade -n storage-preview
storageAccountRG=$(sudo -u $USER_NAME az storage account show --name $STAGING_STORAGE --query 'resourceGroup' | sed -e 's/^"//' -e 's/"$//')
storageContainerName="staging-k3s"
localPath="/home/$USER_NAME/.kube/config"
storageAccountKey=$(sudo -u $USER_NAME az storage account keys list --resource-group $storageAccountRG --account-name $STAGING_STORAGE --query [0].value | sed -e 's/^"//' -e 's/"$//')
sudo -u $USER_NAME az storage container create -n $storageContainerName --account-name $STAGING_STORAGE --account-key $storageAccountKey
sudo -u $USER_NAME az storage azcopy blob upload --container $storageContainerName --account-name $STAGING_STORAGE --account-key $storageAccountKey --source $localPath
