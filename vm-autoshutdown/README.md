# Azure VM Auto-Shutdown (Bicep)

Azure equivalent of [aws-cdk-templates/ec2-autoshutdown](../aws-cdk-templates/ec2-autoshutdown/) — automatically detects VM inactivity and deallocates the instance to stop compute billing.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Resource Group                                                  │
│                                                                  │
│  ┌─────────────┐     ┌───────────────────────────────────────┐   │
│  │ VNet + NSG  │     │ Azure Monitor                         │   │
│  │ (10.0.0.0/16)│     │                                      │   │
│  │             │     │  Metric Alert (CPU < 5% for 15 min)   │   │
│  │ ┌─────────┐ │     │         │                             │   │
│  │ │ Subnet  │ │     │         ▼                             │   │
│  │ │10.0.1.0 │ │     │  Action Group (email notification)    │   │
│  │ └────┬────┘ │     └───────────────────────────────────────┘   │
│  └──────┼──────┘                                                 │
│         │                                                        │
│  ┌──────┴───────────────────────────────────────────────┐        │
│  │ VM (Standard_B2s, Ubuntu 24.04 LTS)                  │        │
│  │                                                      │        │
│  │ Managed Identity ──► Azure REST API (self-deallocate)│        │
│  │                                                      │        │
│  │  ┌────────────────────────────────────────────────┐  │        │
│  │  │ Cloud-Init Auto-Shutdown (systemd timer, 5min) │  │        │
│  │  │                                                │  │        │
│  │  │  Method 1: CPU Monitor                         │  │        │
│  │  │    CPU < 5% for 15 min → deallocate            │  │        │
│  │  │                                                │  │        │
│  │  │  Method 2: SSH Session Detection               │  │        │
│  │  │    0 sessions for 10 min → deallocate          │  │        │
│  │  └────────────────────────────────────────────────┘  │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                  │
│  ┌────────────────────────────────────────┐                      │
│  │ DevTest Lab Schedule (daily 11 PM)     │  ◄── safety net      │
│  └────────────────────────────────────────┘                      │
└──────────────────────────────────────────────────────────────────┘
```

## AWS → Azure Service Mapping

| AWS Service | Azure Equivalent | Notes |
|-------------|-----------------|-------|
| VPC | Virtual Network (VNet) | 10.0.0.0/16 CIDR |
| Security Group | Network Security Group (NSG) | SSH inbound rule |
| EC2 (t4g.small) | VM (Standard_B2s) | 2 vCPUs, 4 GiB RAM |
| IAM Instance Role | System-Assigned Managed Identity | VM Contributor role |
| CloudWatch Alarm → EC2 Stop | VM self-deallocate via Azure REST API | Same thresholds |
| CloudWatch (notification) | Azure Monitor Metric Alert | Email alerts |
| User Data | Cloud-Init (customData) | Same scripts |
| SSM Parameter Store (SSH key) | SSH public key parameter | User provides key |
| EBS (30 GiB GP3) | Premium SSD (30 GiB) | Encrypted, delete on termination |
| — | DevTest Lab Schedule | Azure-native daily safety net |

## Timeout & Threshold Comparison

| Setting | AWS Value | Azure Value |
|---------|-----------|-------------|
| CPU check interval | 5 min | 5 min |
| CPU idle threshold | < 5% | < 5% |
| CPU evaluation periods | 3 consecutive | 3 consecutive |
| CPU total detection | 15 min | 15 min |
| SSH check interval | 5 min | 5 min |
| SSH idle threshold | 2 consecutive | 2 consecutive |
| SSH total detection | 10 min | 10 min |
| Boot grace period | 10 min | 10 min |
| Idle action | EC2 Stop | VM Deallocate (stops billing) |

## Prerequisites

1. **Azure CLI** with Bicep:
   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Install Bicep
   az bicep install
   ```

2. **Azure login**:
   ```bash
   az login
   ```

3. **SSH key pair**:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/azure-autoshutdown -N ""
   ```

## Quick Start

```bash
# Deploy with defaults (Southeast Asia, Standard_B2s)
./deploy.sh

# If Standard_B2s is unavailable in your region/subscription, override VM size:
VM_SIZE=Standard_D2als_v7 ./deploy.sh

# Or deploy manually
RESOURCE_GROUP="autoshutdown-rg"
LOCATION="southeastasia"

az group create --name $RESOURCE_GROUP --location $LOCATION

az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters sshPublicKey="$(cat ~/.ssh/azure-autoshutdown.pub)"
```

## Deployment Commands

```bash
# Validate only (no deployment)
./deploy.sh --validate

# Preview what will be deployed
./deploy.sh --what-if

# Deploy
./deploy.sh

# Delete everything
./deploy.sh --delete
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_GROUP` | `autoshutdown-rg` | Azure resource group name |
| `LOCATION` | `southeastasia` | Azure region (equivalent to AWS ap-southeast-1) |
| `VM_SIZE` | `Standard_B2s` | VM size (if unavailable, try `Standard_D2als_v7`) |
| `SSH_KEY_PATH` | `~/.ssh/azure-autoshutdown.pub` | Path to SSH public key |

## After Deployment

### Connect to the VM
```bash
ssh -i ~/.ssh/azure-autoshutdown azureuser@<PUBLIC_IP>
```

### Monitor auto-shutdown logs
```bash
# On the VM
tail -f /var/log/autoshutdown.log
```

### Check VM status
```bash
az vm get-instance-view \
  --resource-group autoshutdown-rg \
  --name autoshutdown-vm \
  --query instanceView.statuses[1].displayStatus -o tsv
```

### Restart after deallocate
```bash
az vm start --resource-group autoshutdown-rg --name autoshutdown-vm
```

## How It Works

### Method 1: CPU Monitoring (Primary)
1. systemd timer fires every 5 minutes (after 10 min boot grace period)
2. Script reads CPU utilization via `mpstat` (falls back to `/proc/stat`)
3. If CPU < 5%, idle counter increments
4. After 3 consecutive idle checks (15 minutes), VM self-deallocates
5. Deallocate uses Azure REST API via the VM's managed identity
6. VM transitions to "Stopped (deallocated)" — no compute charges

### Method 2: SSH Session Detection (Secondary)
1. Same systemd timer checks for active SSH sessions via `who`
2. If no `pts/*` sessions detected, SSH idle counter increments
3. After 2 consecutive idle checks (10 minutes), VM self-deallocates
4. Same deallocate mechanism as Method 1

### Method 3: Daily Schedule (Safety Net)
- Azure DevTest Lab schedule stops the VM daily at 11 PM (configurable)
- This is an Azure-native feature with no AWS equivalent
- Acts as a safety net in case the inactivity detection misses something

### Self-Deallocate vs. OS Shutdown
On Azure, `shutdown -h now` puts the VM in "Stopped" state but **still incurs compute charges**. This solution uses the Azure REST API `deallocate` action, which transitions the VM to "Stopped (deallocated)" — **no compute charges**. This is equivalent to the AWS CloudWatch alarm's EC2 Stop action.

## File Structure

```
vm-autoshutdown/
├── main.bicep              # Main orchestrator (parameters, modules, role assignment, outputs)
├── main.bicepparam         # Parameter values file
├── modules/
│   ├── network.bicep       # VNet, Subnet, NSG, Public IP, NIC
│   ├── vm.bicep            # VM, Managed Identity, Auto-shutdown schedule
│   └── monitoring.bicep    # Azure Monitor Metric Alert, Action Group
├── scripts/
│   └── cloud-init.yaml     # Cloud-init for CPU + SSH idle detection
├── deploy.sh               # Deployment helper script
└── README.md               # This file
```

## Resources Deployed

| Resource | Type | Purpose |
|----------|------|---------|
| `autoshutdown-vnet` | Virtual Network | Network isolation |
| `autoshutdown-nsg` | Network Security Group | SSH access (port 22) |
| `autoshutdown-pip` | Public IP (Static) | SSH connectivity |
| `autoshutdown-nic` | Network Interface | VM network attachment |
| `autoshutdown-vm` | Virtual Machine | Ubuntu 24.04 LTS compute |
| `shutdown-computevm-*` | DevTest Lab Schedule | Daily auto-shutdown |
| `autoshutdown-ag` | Action Group | Alert notification |
| `autoshutdown-cpu-idle-alert` | Metric Alert | CPU < 5% detection |
| Role Assignment | VM Contributor | Self-deallocate permission |

## Cost Considerations

- **Standard_B2s**: ~$0.042/hr (Southeast Asia pricing)
- **When deallocated**: $0/hr for compute (storage charges still apply)
- **Premium SSD 30 GiB**: ~$4.32/month (charged regardless of VM state)
- **Public IP (Static)**: ~$3.60/month (charged even when VM is deallocated)

## Customization

Edit `main.bicepparam` to customize:
- `location`: Azure region
- `vmSize`: VM size (B1s, B2s, B2ms, B4ms)
- `osDiskSizeGb`: OS disk size (30-256 GiB)
- `autoShutdownTime`: Daily shutdown time (HHmm format)
- `notificationEmail`: Email for CPU idle alerts

Edit `scripts/cloud-init.yaml` to customize:
- `CPU_THRESHOLD`: CPU usage threshold (default: 5%)
- `CPU_IDLE_THRESHOLD`: Consecutive idle checks for CPU (default: 3 = 15 min)
- `SSH_IDLE_THRESHOLD`: Consecutive idle checks for SSH (default: 2 = 10 min)
