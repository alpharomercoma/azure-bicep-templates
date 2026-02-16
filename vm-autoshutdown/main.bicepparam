using './main.bicep'

// =============================================================================
// Azure VM Auto-Shutdown - Parameter Values
// =============================================================================
// Update these values before deployment.
//
// REQUIRED: You must provide your SSH public key.
// Generate one with: ssh-keygen -t ed25519 -f ~/.ssh/azure-autoshutdown
// Then paste the contents of ~/.ssh/azure-autoshutdown.pub below.
// =============================================================================

param location = 'southeastasia'
param baseName = 'autoshutdown'
param adminUsername = 'azureuser'
param vmSize = 'Standard_B2s'
param osDiskSizeGb = 30
param autoShutdownTime = '2300'             // 11:00 PM daily safety net
param autoShutdownTimezone = 'Singapore Standard Time'
param notificationEmail = ''

// IMPORTANT: Replace with your SSH public key
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
