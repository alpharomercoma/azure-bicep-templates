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

param location = 'southeastasia'            // Equivalent to AWS ap-southeast-1
param baseName = 'autoshutdown'
param adminUsername = 'azureuser'
param vmSize = 'Standard_B2s'               // Equivalent to AWS t4g.small
param osDiskSizeGb = 30                     // Same as AWS (30 GiB GP3)
param autoShutdownTime = '2300'             // 11:00 PM daily safety net
param autoShutdownTimezone = 'Singapore Standard Time'
param notificationEmail = ''                // Optional: your@email.com

// IMPORTANT: Replace with your SSH public key
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
