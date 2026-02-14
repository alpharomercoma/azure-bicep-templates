# Azure Bicep Templates

Collection of Azure infrastructure templates using Bicep (Azure's domain-specific IaC language).

---

## Available Templates

### [vm-autoshutdown](./vm-autoshutdown)
Azure VM with **triple automatic shutdown mechanisms** — CPU monitoring, SSH session detection, and a daily DevTest Lab schedule — to prevent idle instances from accruing costs.

- **Instance:** Standard_B2s (2 vCPUs, 4 GiB RAM) · Ubuntu 24.04 LTS · 30 GiB Premium SSD
- **Region:** Southeast Asia (Singapore)
- **Shutdown:** CPU < 5% for 15 min + no SSH for 10 min + daily 11 PM schedule
- **Cost:** ~$46.64/mo (running 24/7) — significantly less with auto-shutdown

---

## Quick Start

```bash
# Navigate to template
cd <template-name>

# Deploy
./deploy.sh

# Validate only
./deploy.sh --validate

# Preview changes
./deploy.sh --what-if

# Delete everything
./deploy.sh --delete
```

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) with Bicep (`az bicep install`)
- Azure subscription with appropriate permissions
- SSH key pair for VM access

## Authentication

```bash
# Interactive login
az login

# Service Principal
az login --service-principal -u <app-id> -p <password> --tenant <tenant-id>

# Managed Identity (from Azure VM/Container)
az login --identity
```

## Documentation

Each Bicep template has its own README with architecture diagrams, deployment commands, cost estimates, and customization options.

## License

MIT
