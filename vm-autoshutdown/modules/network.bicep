// =============================================================================
// Network Module - VNet, Subnet, NSG, Public IP, NIC
// =============================================================================

@description('Azure region for all resources')
param location string

@description('Base name for all resources')
param baseName string

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('CIDR allowed to SSH into the VM (for example x.x.x.x/32)')
param allowedSshCidr string = '127.0.0.1/32'

// =============================================================================
// Network Security Group
// =============================================================================
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${baseName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedSshCidr
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// =============================================================================
// Virtual Network
// =============================================================================
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${baseName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// =============================================================================
// Public IP Address
// =============================================================================
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${baseName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// =============================================================================
// Network Interface
// =============================================================================
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${baseName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: vnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

// =============================================================================
// Outputs
// =============================================================================
output nicId string = nic.id
output publicIpAddress string = publicIp.properties.ipAddress
output publicIpId string = publicIp.id
output vnetName string = vnet.name
output subnetId string = vnet.properties.subnets[0].id
output nsgName string = nsg.name
