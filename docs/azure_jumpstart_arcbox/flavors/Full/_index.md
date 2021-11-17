---
type: docs
title: "Jumpstart ArcBox - Overview"
linkTitle: "Jumpstart ArcBox"
weight: 3
---

## Jumpstart ArcBox "Full" Edition - Overview

ArcBox is a solution that provides an easy to deploy sandbox for all things Azure Arc. ArcBox is designed to be completely self-contained within a single Azure subscription and resource group, which will make it easy for a user to get hands-on with all available Azure Arc technology with nothing more than an available Azure subscription.

![ArcBox architecture diagram](./arch_full.png)

### Use cases

* Sandbox environment for getting hands-on with Azure Arc technologies
* Accelerator for Proof-of-concepts or pilots
* Training tool for Azure Arc skills development
* Demo environment for customer presentations or events
* Rapid integration testing platform

## Azure Arc capabilities available in ArcBox

### Azure Arc-enabled servers

![ArcBox servers diagram](./servers.png)

ArcBox includes five Azure Arc-enabled server resources that are hosted using nested virtualization in Azure. As part of the deployment, a Hyper-V host (ArcBox-Client) is deployed with five guest virtual machines. These machines, _ArcBox-Win2k22_, _ArcBox-Win2k19_, _ArcBox-SQL_, _ArcBox-CentOS_, and _ArcBox-Ubuntu_ are connected as Azure Arc-enabled servers via the ArcBox automation.

### Azure Arc-enabled Kubernetes

![ArcBox Kubernetes diagram](./k8s.png)

ArcBox deploys one single-node Rancher K3s cluster running on an Azure virtual machine. This cluster is then connected to Azure as an Azure Arc-enabled Kubernetes resource (_ArcBox-K3s_).

### Azure Arc-enabled data services

ArcBox deploys one single-node Rancher K3s cluster (_ArcBox-CAPI-MGMT_), which is then transformed to a [Cluster API](https://cluster-api.sigs.k8s.io/user/concepts.html) management cluster with the Azure CAPZ provider, and a workload cluster is deployed onto the management cluster. The Azure Arc-enabled data services and data controller are deployed onto this workload cluster via a PowerShell script that runs when first logging into ArcBox-Client virtual machine.

![ArcBox data services diagram](./dataservices2.png)

### Hybrid Unified Operations

ArcBox deploys several management and operations services that work with ArcBox's Azure Arc resources. These resources include an an Azure Automation account, an Azure Log Analytics workspace with the Update Management solution, an Azure Monitor workbook, Azure Policy assignments for deploying Log Analytics agents on Windows and Linux Azure Arc-enabled servers, Azure Policy assignment for adding tags to resources, and a storage account used for staging resources needed for the deployment automation.

![ArcBox unified operations diagram](./unifiedops.png)

## ArcBox Azure Consumption Costs

ArcBox resources generate Azure Consumption charges from the underlying Azure resources including core compute, storage, networking and auxilliary services. These services generate approximately $30-40 USD per day. Note that Azure consumption costs vary depending the region where ArcBox is deployed. Be mindful of your ArcBox deployments and ensure that you disable or delete ArcBox resources when not in use to avoid unwanted charges. Users may review cost analysis of ArcBox by using [Azure Cost Analysis](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/quick-acm-cost-analysis).

## Deployment Options and Automation Flow

ArcBox provides multiple paths for deploying and configuring ArcBox resources. Deployment options include:

* Azure Portal
* ARM template via Azure CLI
* Bicep
* Terraform

![Deployment flow diagram for ARM-based deployments](./deploymentflow.png)

![Deployment flow diagram for Terraform-based deployments](./deploymentflow_tf.png)

ArcBox uses an advanced automation flow to deploy and configure all necessary resources with minimal user interaction. The previous diagrams provide an overview of the deployment flow. A high-level summary of the deployment is:

* User deploys the primary ARM template (azuredeploy.json), Bicep file (main.bicep), or Terraform plan (main.tf). These objects contain several nested objects that will run simultaneously.
  * ClientVM ARM template/plan - deploys the Client Windows VM. This is the Hyper-V host VM where all user interactions with the environment are made from.
  * Storage account template/plan - used for staging files in automation scripts
  * Management artifacts template/plan - deploys Azure Log Analytics workspace and solutions and Azure Policy artifacts
* User remotes into Client Windows VM, which automatically kicks off multiple scripts that:
  * Deploy and configure five (5) nested virtual machines in Hyper-V
    * Windows Server 2022 VM - onboarded as Azure Arc-enabled Server
    * Windows Server 2019 VM - onboarded as Azure Arc-enabled Server
    * Windows VM running SQL Server - onboarded as Azure Arc-enabled SQL Server (as well as Azure Arc-enabled Server)
    * Ubuntu VM - onboarded as Azure Arc-enabled Server
    * CentOS VM - onboarded as Azure Arc-enabled server
  * Deploy an Azure Monitor workbook that provides example reports and metrics for monitoring ArcBox components

## Prerequisites

* ArcBox Full requires 52 DSv3-series vCPUs when deploying with default parameters such as VM series/size. Ensure you have sufficient vCPU quota available in your Azure subscription and the region where you plan to deploy ArcBox. You can use the below Az CLI command to check your vCPU utilization.

  ```shell
  az vm list-usage --location <your location> --output table
  ```

  ![Screenshot showing az vm list-usage](./azvmlistusage.png)

* [Install or update Azure CLI to version 2.15.0 and above](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest). Use the below command to check your current installed version.

  ```shell
  az --version
  ```

* Login to AZ CLI using the ```az login``` command.

* Register necessary Azure resource providers by running the following commands.

  ```shell
  az provider register --namespace Microsoft.Kubernetes --wait
  az provider register --namespace Microsoft.KubernetesConfiguration --wait
  az provider register --namespace Microsoft.ExtendedLocation --wait
  az provider register --namespace Microsoft.AzureArcData --wait
  ```

* Create Azure service principal (SP)

    To deploy ArcBox an Azure service principal assigned with the "Contributor" role is required. To create it login to your Azure account run the below command (this can also be done in [Azure Cloud Shell](https://shell.azure.com/)).

    ```shell
    az login
    az ad sp create-for-rbac -n "<Unique SP Name>" --role contributor
    ```

    For example:

    ```shell
    az ad sp create-for-rbac -n "http://AzureArcBox" --role contributor
    ```

    Output should look like this:

    ```json
    {
    "appId": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "displayName": "AzureArcBox",
    "name": "http://AzureArcBox",
    "password": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX",
    "tenant": "XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    }
    ```

    > **Note: The Jumpstart scenarios are designed with as much ease of use in-mind and adhering to security-related best practices whenever possible. It is optional but highly recommended to scope the service principal to a specific [Azure subscription and resource group](https://docs.microsoft.com/en-us/cli/azure/ad/sp?view=azure-cli-latest) as well considering using a [less privileged service principal account](https://docs.microsoft.com/en-us/azure/role-based-access-control/best-practices)**

* [Generate SSH Key](https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/) (or use existing ssh key)

  ```shell
  ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
  ```

## ArcBox Azure Region Compatibility

ArcBox must be deployed to one of the following regions. Deploying ArcBox outside of these regions may result in unexpected results or deployment errors.

* East US
* East US 2
* West US 2
* North Europe
* France Central
* UK South
* Southeast Asia

## Deployment Option 1: Azure Portal

* Click the <a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmicrosoft%2Fazure_arc%2Farcbox_flavors%2FARM%2Fazure_jumpstart_arcbox%2Fazuredeploy.json" target="_blank"><img src="https://aka.ms/deploytoazurebutton"/></a> button and enter values for the the ARM template parameters.

  ![Screenshot showing Azure Portal deployment of ArcBox](./portaldeploy.png)

  ![Screenshot showing Azure Portal deployment of ArcBox](./portaldeployinprogress.png)

  ![Screenshot showing Azure Portal deployment of ArcBox](./portaldeploymentcomplete.png)

## Deployment Option 2: ARM template with Azure CLI

* Clone the Azure Arc Jumpstart repository

    ```shell
    git clone https://github.com/microsoft/azure_arc.git
    ```

* Edit the [azuredeploy.parameters.json](https://github.com/microsoft/azure_arc/blob/arcbox_flavors/azure_jumpstart_arcbox/azuredeploy.parameters.json) ARM template parameters file and supply some values for your environment.

  * *sshRSAPublicKey* - Your SSH public key
  * *spnClientId* - Your Azure service principal id
  * *spnClientSecret* - Your Azure service principal secret
  * *spnTenantId* - Your Azure tenant id
  * *windowsAdminUsername* - Client Windows VM Administrator name
  * *windowsAdminPassword* - Client Windows VM Password. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long.
  * *myIpAddress* - Your local IP address. This is used to allow remote RDP and SSH connections to the Client Windows VM and K3s Rancher VM.
  * *logAnalyticsWorkspaceName* - Unique name for the ArcBox log analytics workspace
  * *flavor* - Use the value "Full" to specify that you want to deploy the complete version of ArcBox (ArcBox Full)

    ![Screenshot showing example parameters](./parameters.png)

* Now you will deploy the ARM template. Navigate to the local cloned [deployment folder](https://github.com/microsoft/azure_arc/tree/arcbox_flavors/azure_jumpstart_arcbox) and run the below command:

  ```shell
  az group create --name <Name of the Azure resource group> --location <Azure Region>
  az deployment group create \
  --resource-group <Name of the Azure resource group> \
  --template-file azuredeploy.json \
  --parameters azuredeploy.parameters.json 
  ```

  ![Screenshot showing az group create](./azgroupcreate.png)

  ![Screenshot showing az deployment group create](./azdeploy.png)

## Deployment Option 3: Bicep deployment via Azure CLI

* Clone the Azure Arc Jumpstart repository

  ```shell
  git clone https://github.com/microsoft/azure_arc.git
  ```

* Upgrade to latest Bicep version

  ```shell
  az bicep upgrade
  ```

* Edit the [main.parameters.json](https://github.com/microsoft/azure_arc/blob/arcbox_flavors/azure_jumpstart_arcbox/bicep/main.parameters.json) template parameters file and supply some values for your environment.

  * *sshRSAPublicKey* - Your SSH public key

  * *spnClientId* - Your Azure service principal id

  * *spnClientSecret* - Your Azure service principal secret

  * *spnTenantId* - Your Azure tenant id

  * *windowsAdminUsername* - Client Windows VM Administrator name

  * *windowsAdminPassword* - Client Windows VM Password. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long.

  * *myIpAddress* - Your local IP address. This is used to allow remote RDP and SSH connections to the Client Windows VM and K3s Rancher VM.

  * *logAnalyticsWorkspaceName* - Unique name for the ArcBox log analytics workspace

  * *flavor* - Use the value "Full" to specify that you want to deploy the full version of ArcBox

  ![Screenshot showing example parameters](./parameters_bicep.png)

* Now you will deploy the Bicep file. Navigate to the local cloned [deployment folder](https://github.com/microsoft/azure_arc/tree/arcbox_flavors/azure_jumpstart_arcbox/bicep) and run the below command:

  ```shell
  az login
  az group create --name "<resource-group-name>"  --location "<preferred-location>"
  az deployment group create -g "<resource-group-name>" -f "main.bicep" -p "main.parameters.json"
  ```

* After deployment, you should see the ArcBox resources inside your resource group.

  ![Screenshot showing az deployment group create](./deployedresources.png)

## Deployment Option 4: Terraform Deployment

* Clone the Azure Arc Jumpstart repository

  ```shell
  git clone https://github.com/microsoft/azure_arc.git
  ```

* Download and install the latest version of Terraform [here](https://www.terraform.io/downloads.html)

  > **NOTE: Terraform 1.x or higher is supported for this deployment. Tested with Terraform v1.011.**

* Create a `terraform.tfvars` file in the root of the terrform directory and supply some values for your environment.

  ```HCL
  azure_location    = "westus2"
  spn_client_id     = "1414133c-9786-53a4-b231-f87c143ebdb1"
  spn_client_secret = "tgG7R~ef4w1rcvzfNmZoFNhgpRrMw25iLXEcS"
  spn_tenant_id     = "33572583-d294-5b56-c4e6-dcf9a297ec17"
  user_ip_address   = "24.17.99.79"
  client_admin_ssh  = "C:/Temp/rsa.pub"
  deployment_flavor = "Full"
  ```

* Example `terraform tfvars`:

  ![terraform.tfvars](./tfvars_file.png)

* Variable Reference:

  * ***azure_location*** - Azure location code (e.g. 'eastus', 'westus2', etc.)

  * *resource_group_name* - Resource group which will contain all of the ArcBox artifacts

  * ***spn_client_id*** - Your Azure service principal id

  * ***spn_client_secret*** - Your Azure service principal secret

  * ***spn_tenant_id*** - Your Azure tenant id

  * ***user_ip_address*** - Your local IP address. This is used to allow remote RDP and SSH connections to the Client Windows VM and K3s Rancher VM. If you don't know your public IP, you can find it [here](https://www.whatismyip.com/)

  * ***client_admin_ssh*** - SSH public key path, used for Linux VMs

  * ***deployment_flavor*** - Use the value "Full" to specify that you want to deploy the full version of ArcBox

  * *client_admin_username* - Admin username for Windows & Linux VMs

  * *client_admin_password* - Admin password for Windows VMs. Password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. The value must be between 12 and 123 characters long.

  * *workspace_name* - Unique name for the ArcBox Log Analytics workspace

  > **NOTE: Any variables in **bold** are required. If any optional parameters are not provided, defaults will be used.**

* Now you will deploy the Terraform file. Navigate to the local cloned [deployment folder](https://github.com/microsoft/azure_arc/tree/main/azure_jumpstart_arcbox/bicep) and run the commands below:

  ```shell
  terraform init
  terraform plan -out=infra.out
  terraform apply "infra.out"
  ```
  
* Example output from `terraform init`:

  ![terraform init](./terraform_init.png)

* Example output from `terraform plan -out=infra.out`:

  ![terraform plan](./terraform_plan.png)

* Example output from `terraform apply "infra.out"`:

  ![terraform plan](./terraform_apply.png)

## Start post-deployment automation

* After deployment, you should see the ArcBox resources inside your resource group.

  ![Screenshot showing az deployment group create](./deployedresources.png)

* Open a remote desktop connection into _ArcBox-Client_. Upon logging in, multiple automated scripts will open and start running. These scripts usually take 10-20 minutes to finish and once completed the script windows will close. At this point, the deployment is complete.

  ![Screenshot showing ArcBox-Client](./automation5.png)

  ![Screenshot showing ArcBox resources in Azure Portal](./rgarc.png)

## Using ArcBox

After deployment is complete, its time to start exploring ArcBox. Most interactions with ArcBox will take place either from Azure itself (Azure Portal, CLI or similar) or from inside the ArcBox-Client virtual machine. When remoted into the client VM, here are some things to try:

* Open Hyper-V and access the Azure Arc-enabled servers
  * Username: arcdemo
  * Password: ArcDemo123!!

  ![Screenshot showing ArcBox Client VM with Hyper-V](./hypervterminal.png)

* Use the included [kubectx](https://github.com/ahmetb/kubectx) tool to switch Kubernetes contexts between the Rancher K3s and AKS clusters.

  ```shell
  kubectx
  kubectx arcbox-capi
  kubectl get nodes
  kubectl get pods -n arc
  kubectx arcbox-k3s
  kubectl get nodes
  ```

  ![Screenshot showing usage of kubectx](./kubectx.png)

* Open Azure Data Studio and explore the SQL MI and PostgreSQL Hyperscale instances.

  ![Screenshot showing Azure Data Studio usage](./azdatastudio.png)

### ArcBox Azure Monitor workbook

Open the [ArcBox Azure Monitor workbook](https://azurearcjumpstart.io/azure_jumpstart_arcbox/workbook/) and explore the visualizations and reports of hybrid cloud resources. A [dedicated README](https://azurearcjumpstart.io/azure_jumpstart_arcbox/workbook/) is available with more detail on usage of the workbook.

  ![Screenshot showing Azure Monitor workbook usage](./workbook.png)

### Azure Arc-enabled data services operations

Open the [data services operations page](https://azurearcjumpstart.io/azure_jumpstart_arcbox/data_ops/) and explore various ways you can perform operations against the Azure Arc-enabled data services deployed with ArcBox.

  ![Screenshot showing Grafana dashboard](./activity1.png)

### Included tools

The following tools are including on the ArcBox-Client VM.

* Azure Data Studio with Arc and PostgreSQL extensions
* kubectl, kubectx, helm
* Chocolatey
* Visual Studio Code
* Putty
* 7zip
* Terraform
* Git
* SqlQueryStress

### Next steps
  
ArcBox is a sandbox that can be used for a large variety of use cases, such as an environment for testing and training or kickstarter for proof of concept projects. Ultimately, you are free to do whatever you wish with ArcBox. Some suggested next steps for you to try in your ArcBox are:

* Deploy sample databases to the PostgreSQL Hyperscale instance or to the SQL Managed Instance
* Use the included kubectx to switch contexts between the two Kubernetes clusters
* Deploy GitOps configurations with Azure Arc-enabled Kubernetes
* Build policy initiatives that apply to your Azure Arc-enabled resources
* Write and test custom policies that apply to your Azure Arc-enabled resources
* Incorporate your own tooling and automation into the existing automation framework
* Build a certificate/secret/key management strategy with your Azure Arc resources

Do you have an interesting use case to share? Submit an issue on GitHub with your idea and we will consider it for future releases!

## Clean up the deployment

To clean up your deployment, simply delete the resource group using Azure CLI or Azure Portal.

```shell
az group delete -n <name of your resource group>
```

![Screenshot showing az group delete](./azdelete.png)

![Screenshot showing group delete from Azure Portal](./portaldelete.png)

## Basic Troubleshooting

Occasionally deployments of ArcBox may fail at various stages. Common reasons for failed deployments include:

* Invalid service principal id, service principal secret provided in _azuredeploy.parameters.json_ file.
* Invalid SSH public key provided in _azuredeploy.parameters.json_ file.
  * An example SSH public key is shown here. Note that the public key includes "ssh-rsa" at the beginning. The entire value should be included in your _azuredeploy.parameters.json_ file.

    ```console
    ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAklOUpkDHrfHY17SbrmTIpNLTGK9Tjom/BWDSU
    GPl+nafzlHDTYW7hdI4yZ5ew18JH4JW9jbhUFrviQzM7xlELEVf4h9lFX5QVkbPppSwg0cda3
    Pbv7kOdJ/MTyBlWXFCR+HAo3FXRitBqxiX1nKhXpHAZsMciLq8V6RjsNAQwdsdMFvSlVK/7XA
    t3FaoJoAsncM1Q9x5+3V0Ww68/eIFmb1zuUFljQJKprrX88XypNDvjYNby6vw/Pb0rwert/En
    mZ+AW4OZPnTPI89ZPmVMLuayrD2cE86Z/il8b+gw3r3+1nKatmIkjn2so1d01QraTlMqVSsbx
    NrRFi9wrf+M7Q== myname@mylaptop.local
    ```

* Not enough vCPU quota available in your target Azure region - check vCPU quota and ensure you have at least 52 available. See the [prerequisites](#prerequisites) section for more details.
* Target Azure region does not support all required Azure services - ensure you are running ArcBox in one of the supported regions listed in the above section "ArcBox Azure Region Compatibility".
* "BadRequest" error message when deploying - this error returns occassionally when the Log Analytics solutions in the ARM templates are deployed. Typically, waiting a few minutes and re-running the same deployment resolves the issue. Alternatively, you can try deploying to a different Azure region.

  ![Screenshot showing BadRequest errors in Az CLI](./error_badrequest.png)

  ![Screenshot showing BadRequest errors in Azure Portal](./error_badrequest2.png)

Occasionally, you may need to review log output from scripts that run on the ArcBox-Client, ArcBox-CAPI or ArcBox-K3s virtual machines in case of deployment failures. Locations of logs for various script outputs is listed here:

* ArcBox-Client
  * C:\ArcBox\ArcServersLogonScript.log
  * C:\ArcBox\DataServicesLogonScript.log
  * C:\ArcBox\
* ArcBox-CAPI
  * /var/lib/waagent/custom-script/download/0/installCAPI.log
* ArcBox-K3s
  * /var/lib/waagent/custom-script/download/0/installK3s.log

If you are still having issues deploying ArcBox, please [submit an issue](https://github.com/microsoft/azure_arc/issues/new/choose) on GitHub and include the Azure region you are deploying to, the flavor of ArcBox you are trying to deploy, and the output of the relevant logs listed above.

## Known issues

* Azure Arc-enabled SQL Server assessment report not always visible in Azure Portal
