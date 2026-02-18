// =============================================================================
// Azure VM Auto-Shutdown - Main Deployment Template
// =============================================================================
//
// This Bicep template deploys an Azure VM with automatic shutdown based on
// inactivity detection, using a multi-signal quorum approach:
//
// 1. CPU Monitoring (Primary):
//    - Checks CPU utilization every 5 minutes
//    - Deallocates VM after 3 consecutive idle checks (15 min, CPU < 5%)
//
// 2. SSH Session Detection:
//    - Checks for active SSH sessions every 5 minutes
//    - Requires no active sessions for 2 consecutive checks (10 min)
// 3. Network Throughput Detection:
//    - Requires low combined inbound/outbound throughput for 3 checks (15 min)
// 4. Disk I/O Detection:
//    - Requires near-zero read/write IOPS and throughput for 3 checks (15 min)
// 5. Decision Rule:
//    - Deallocate when SSH is idle and at least 2 of 3 workload signals are idle
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

@description('CIDR allowed to SSH into the VM (for example x.x.x.x/32)')
param allowedSshCidr string = '127.0.0.1/32'

// =============================================================================
// Variables
// =============================================================================

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
    allowedSshCidr: allowedSshCidr
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

@description('CIDR allowed to SSH into the VM')
output sshAllowedCidr string = allowedSshCidr
