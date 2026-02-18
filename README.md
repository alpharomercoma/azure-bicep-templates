# Azure Bicep Templates

Azure infrastructure templates using Bicep.

## Templates

### [vm-autoshutdown](./vm-autoshutdown)

Azure VM with automatic shutdown on inactivity (multi-signal quorum: CPU + SSH + network + disk + DevTest Lab schedule).

| Property | Value |
|----------|-------|
| Instance | Standard_B2s (2 vCPUs, 4 GiB) |
| OS | Ubuntu 24.04 LTS |
| Region | southeastasia (Singapore) |
| Storage | 30 GiB Premium SSD |
| Cost | ~$47/mo (running 24/7) |

## Quick Start

```bash
cd <template-name>
./deploy.sh              # deploy
./deploy.sh --validate   # validate only
./deploy.sh --what-if    # preview changes
./deploy.sh --delete     # delete everything
```

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) with Bicep (`az bicep install`)
- Azure subscription with appropriate permissions
- SSH key pair (`ssh-keygen -t ed25519`)

## Helper Scripts

| Script | Description |
|--------|-------------|
| `create-start-script.sh` | Generate a one-command launcher for Azure VMs |
| `destroy-project.sh` | Safely destroy Azure resource groups with confirmation |

## License

MIT
