# Azure VM Auto-Shutdown (Bicep)

Azure Bicep template that deploys a Virtual Machine with **triple automatic shutdown mechanisms** to prevent idle instances from accruing unnecessary costs.

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

## Auto-Shutdown Mechanisms

### Method 1: CPU Monitoring (Primary)
1. Systemd timer fires every 5 minutes (after 10 min boot grace period)
2. Script reads CPU utilization via `mpstat` (falls back to `/proc/stat`)
3. If CPU < 5%, idle counter increments
4. After 3 consecutive idle checks (15 minutes), VM self-deallocates
5. Deallocate uses Azure REST API via the VM's managed identity
6. VM transitions to "Stopped (deallocated)" — **no compute charges**

### Method 2: SSH Session Detection (Secondary)
1. Same systemd timer checks for active SSH sessions via `who`
2. If no `pts/*` sessions detected, SSH idle counter increments
3. After 2 consecutive idle checks (10 minutes), VM self-deallocates

### Method 3: Daily Schedule (Safety Net)
- Azure DevTest Lab schedule stops the VM daily at 11 PM (configurable)
- Azure-native feature that acts as a safety net in case inactivity detection misses something

| Setting | Value |
|---------|-------|
| CPU check interval | 5 min |
| CPU idle threshold | < 5% |
| CPU evaluation periods | 3 consecutive |
| CPU total detection | 15 min |
| SSH check interval | 5 min |
| SSH idle threshold | 2 consecutive |
| SSH total detection | 10 min |
| Boot grace period | 10 min |
| Idle action | VM Deallocate (stops billing) |

> **Note:** On Azure, `shutdown -h now` puts the VM in "Stopped" state but **still incurs compute charges**. This solution uses the Azure REST API `deallocate` action, which transitions the VM to "Stopped (deallocated)" — **no compute charges**.

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
| `LOCATION` | `southeastasia` | Azure region |
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
| `autoshutdown-vnet` | Virtual Network | Network isolation (10.0.0.0/16) |
| `autoshutdown-nsg` | Network Security Group | SSH access (port 22) |
| `autoshutdown-pip` | Public IP (Static, Standard SKU) | SSH connectivity |
| `autoshutdown-nic` | Network Interface | VM network attachment |
| `autoshutdown-vm` | Virtual Machine (Standard_B2s) | Ubuntu 24.04 LTS compute (2 vCPUs, 4 GiB RAM) |
| `shutdown-computevm-*` | DevTest Lab Schedule | Daily auto-shutdown at 11 PM |
| `autoshutdown-ag` | Action Group | Alert email notification |
| `autoshutdown-cpu-idle-alert` | Metric Alert | CPU < 5% detection |
| Role Assignment | VM Contributor | Self-deallocate permission |

## Cost Estimate

Pricing based on the default region **Southeast Asia**.

| Resource | Approximate Cost |
|----------|-----------------|
| Standard_B2s VM (Linux, $0.0528/hr) | ~$38.54/mo (running 24/7) |
| Premium SSD 30 GiB (P4 = 32 GiB tier) | ~$4.45/mo |
| Public IP (Static, Standard SKU) | ~$3.65/mo |
| VNet + NSG | $0.00 |
| Azure Monitor alert | $0.00 (included) |
| **Total (running 24/7)** | **~$46.64/mo** |

With auto-shutdown, actual costs will be significantly lower based on usage. Use the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) for other regions.

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

## Cleanup

```bash
./deploy.sh --delete
```
