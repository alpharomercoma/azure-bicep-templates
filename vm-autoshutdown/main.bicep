// =============================================================================
// Azure VM Auto-Shutdown - Main Deployment Template
// =============================================================================
//
// This Bicep template deploys an Azure VM with automatic shutdown based on
// inactivity detection, using a dual-method approach:
//
// 1. CPU Monitoring (Primary):
//    - Checks CPU utilization every 5 minutes
//    - Deallocates VM after 3 consecutive idle checks (15 min, CPU < 5%)
//
// 2. SSH Session Detection (Secondary):
//    - Checks for active SSH sessions every 5 minutes
//    - Deallocates VM after 2 consecutive idle checks (10 min, 0 sessions)
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Azure region for all resources (default: resource group location)')
param location string = resourceGroup().location

@description('Base name prefix for all resources')
@minLength(3)
@maxLength(20)
param baseName string = 'autoshutdown'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('SSH public key for VM authentication. Generate with: ssh-keygen -t ed25519')
@secure()
param sshPublicKey string

@description('VM size. Default Standard_B2s provides 2 vCPUs and 4 GiB RAM. If unavailable in your region/subscription, try Standard_D2as_v5, Standard_D2als_v7, or run: az vm list-skus --location <region> --size Standard_B2 --output table')
param vmSize string = 'Standard_B2s'

@description('OS disk size in GiB')
@minValue(30)
@maxValue(256)
param osDiskSizeGb int = 30

@description('Daily auto-shutdown time in HHmm format (24hr). Safety net beyond inactivity detection.')
param autoShutdownTime string = '2300'

@description('Timezone for the daily auto-shutdown schedule')
param autoShutdownTimezone string = 'Singapore Standard Time'

@description('Email address for CPU idle alert notifications (leave empty to skip)')
param notificationEmail string = ''

// =============================================================================
// Variables
// =============================================================================

// Virtual Machine Contributor role definition ID
// Allows the VM's managed identity to deallocate itself
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

// Load cloud-init configuration from file
var cloudInitData = base64(loadTextContent('scripts/cloud-init.yaml'))

// =============================================================================
// Module: Network Infrastructure
// =============================================================================
module network 'modules/network.bicep' = {
  name: '${baseName}-network-deployment'
  params: {
    location: location
    baseName: baseName
  }
}

// =============================================================================
// Module: Virtual Machine
// =============================================================================
module vm 'modules/vm.bicep' = {
  name: '${baseName}-vm-deployment'
  params: {
    location: location
    baseName: baseName
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    nicId: network.outputs.nicId
    vmSize: vmSize
    osDiskSizeGb: osDiskSizeGb
    autoShutdownTime: autoShutdownTime
    autoShutdownTimezone: autoShutdownTimezone
    cloudInitData: cloudInitData
  }
}

// =============================================================================
// Role Assignment: VM Contributor for Self-Deallocate
// =============================================================================
// Grants the VM's system-assigned managed identity the Virtual Machine
// Contributor role, scoped to the resource group. This allows the cloud-init
// script to call the Azure REST API to deallocate the VM when idle.
//

resource vmContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, baseName, vmContributorRoleId)
  properties: {
    principalId: vm.outputs.vmPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Module: Monitoring (Azure Monitor Metric Alert)
// =============================================================================
module monitoring 'modules/monitoring.bicep' = {
  name: '${baseName}-monitoring-deployment'
  params: {
    location: location
    baseName: baseName
    vmResourceId: vm.outputs.vmId
    notificationEmail: notificationEmail
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('VM resource ID')
output vmId string = vm.outputs.vmId

@description('VM name')
output vmName string = vm.outputs.vmName

@description('VM public IP address')
output publicIpAddress string = network.outputs.publicIpAddress

@description('SSH command to connect to the VM')
output sshCommand string = 'ssh ${adminUsername}@${network.outputs.publicIpAddress}'

@description('Command to start the VM after it has been deallocated')
output startVmCommand string = 'az vm start --resource-group ${resourceGroup().name} --name ${vm.outputs.vmName}'

@description('Command to check VM status')
output vmStatusCommand string = 'az vm get-instance-view --resource-group ${resourceGroup().name} --name ${vm.outputs.vmName} --query instanceView.statuses[1].displayStatus -o tsv'

@description('Azure Monitor alert name')
output alertName string = monitoring.outputs.alertName

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment region')
output region string = location
