# Azure VM Auto-Shutdown

Azure VM with automatic shutdown on inactivity detection.

## Specifications

| Property | Value |
|----------|-------|
| VM Size | Standard_B2s (2 vCPUs, 4 GiB) |
| OS | Ubuntu 24.04 LTS |
| Region | southeastasia (Singapore) |
| Storage | 30 GiB Premium SSD |
| Identity | System-assigned Managed Identity |

## Auto-Shutdown

### Multi-Signal Idle Detection (Cloud-Init)

Systemd timer checks these signals every 5 minutes:
- CPU utilization via `mpstat` (`< 5%`, 15 minutes)
- SSH sessions via `who` (`0 sessions`, 10 minutes)
- Network throughput (`RX+TX < 20 KB/s`, 15 minutes)
- Disk I/O (`< 2 IOPS` and `< 10 KB/s`, 15 minutes)

Deallocation decision uses a quorum model:
- `SSH idle` **AND**
- at least `2 of 3` workload signals idle (`CPU`, `Network`, `Disk`)

### DevTest Lab Schedule (Safety Net)

Azure-native daily auto-shutdown at 11 PM (configurable). Acts as a safety net.

> **Note:** On Azure, `shutdown -h now` keeps the VM in "Stopped" state (still billed). This solution uses the Azure REST API `deallocate` action → "Stopped (deallocated)" = no compute charges.

## Architecture

```
Resource Group
├── VNet (10.0.0.0/16) + NSG (SSH port 22)
├── Public IP (Static) + NIC
├── VM (Standard_B2s, Ubuntu 24.04)
│   ├── Managed Identity → Azure REST API (self-deallocate)
│   └── Cloud-Init (systemd timer, 5 min)
│       ├── CPU Monitor (< 5%, 15 min)
│       ├── SSH Detection (0 sessions, 10 min)
│       ├── Network Monitor (RX+TX < 20 KB/s, 15 min)
│       └── Disk I/O Monitor (< 2 IOPS and < 10 KB/s, 15 min)
├── Azure Monitor Metric Alert (CPU < 5%, 15 min)
└── DevTest Lab Schedule (daily 11 PM)
```

## Deploy

```bash
cd vm-autoshutdown
./deploy.sh              # deploy
./deploy.sh --validate   # validate only
./deploy.sh --what-if    # preview changes
./deploy.sh --delete     # delete everything
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_GROUP` | `autoshutdown-rg` | Resource group name |
| `LOCATION` | `southeastasia` | Azure region |
| `VM_SIZE` | `Standard_B2s` | VM size |
| `SSH_KEY_PATH` | `~/.ssh/azure-autoshutdown.pub` | SSH public key path |

## Connect

```bash
ssh -i ~/.ssh/azure-autoshutdown azureuser@<PUBLIC_IP>
```

## Restart After Shutdown

```bash
az vm start --resource-group autoshutdown-rg --name autoshutdown-vm
```

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| Standard_B2s (730 hrs) | ~$38.54 |
| 30 GiB Premium SSD | ~$4.45 |
| Public IP (Static) | ~$3.65 |
| **Total (24/7)** | **~$46.64** |

With auto-shutdown, actual costs depend on usage.

## Cleanup

```bash
./deploy.sh --delete
```
