// =============================================================================
// VM Module - Virtual Machine with Cloud-Init & Auto-Shutdown Schedule
// =============================================================================
// Equivalent to AWS EC2 Instance (t4g.small) with User Data
// =============================================================================

@description('Azure region for all resources')
param location string

@description('Base name for all resources')
param baseName string

@description('Admin username for the VM')
param adminUsername string

@description('SSH public key for authentication')
@secure()
param sshPublicKey string

@description('Network interface ID')
param nicId string

@description('VM size (equivalent to AWS t4g.small)')
param vmSize string = 'Standard_B2s'

@description('OS disk size in GiB')
param osDiskSizeGb int = 30

@description('Daily auto-shutdown time (HHmm format, 24hr)')
param autoShutdownTime string = '2300'

@description('Timezone for auto-shutdown schedule')
param autoShutdownTimezone string = 'Singapore Standard Time'

@description('Cloud-init custom data (base64 encoded)')
param cloudInitData string

// =============================================================================
// Virtual Machine (equivalent to AWS EC2 Instance)
// =============================================================================
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${baseName}-vm'
  location: location
  identity: {
    // System-assigned managed identity (equivalent to AWS IAM Instance Role)
    // Used by the VM to call Azure REST API for self-deallocation
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      // Standard_B2s: 2 vCPUs, 4 GiB RAM (comparable to AWS t4g.small)
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${baseName}-vm'
      adminUsername: adminUsername
      customData: cloudInitData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      // Ubuntu 24.04 LTS (equivalent to Ubuntu 24.04 ARM64 on AWS)
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: '${baseName}-osdisk'
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          // Premium SSD (equivalent to AWS GP3)
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicId
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    securityProfile: {
      // Trusted Launch: Azure security best practice for Gen2 VMs
      // Provides Secure Boot (prevents boot-level malware) and vTPM
      // (virtual Trusted Platform Module for measured boot attestation)
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// =============================================================================
// Auto-Shutdown Schedule (Azure-native daily shutdown safety net)
// =============================================================================
// This is an Azure-specific feature with no direct AWS equivalent.
// It provides a daily time-based auto-shutdown as an additional safety net
// on top of the inactivity-based detection.
resource autoShutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vm.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimezone
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================
output vmId string = vm.id
output vmName string = vm.name
output vmPrincipalId string = vm.identity.principalId
