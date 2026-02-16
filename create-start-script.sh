#!/usr/bin/env bash
# Azure VM Start Script Generator
# Creates a one-command launcher to start and SSH into an Azure VM.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

echo -e "${BLUE}Azure VM Start Script Generator${NC}\n"

# Check prerequisites
command -v az &>/dev/null || { echo -e "${RED}Error: Azure CLI not installed${NC}"; exit 1; }
az account show &>/dev/null || { echo -e "${RED}Error: Not authenticated. Run: az login${NC}"; exit 1; }

# List resource groups
echo -e "${BLUE}Resource groups:${NC}"
az group list --query '[].{Name:name,Location:location}' --output table

echo ""
read -p "Resource group [autoshutdown-rg]: " RG
RG="${RG:-autoshutdown-rg}"

# List VMs in resource group
echo -e "\n${BLUE}VMs in ${RG}:${NC}"
az vm list --resource-group "$RG" --query '[].{Name:name,Size:hardwareProfile.vmSize,State:powerState}' --output table --show-details 2>/dev/null

echo ""
read -p "VM name [autoshutdown-vm]: " VM_NAME
VM_NAME="${VM_NAME:-autoshutdown-vm}"

# SSH key setup
read -p "Path to SSH private key [~/.ssh/azure-autoshutdown]: " SSH_KEY
SSH_KEY="${SSH_KEY:-$HOME/.ssh/azure-autoshutdown}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"

read -p "SSH username [azureuser]: " SSH_USER
SSH_USER="${SSH_USER:-azureuser}"

SCRIPT_NAME="start-azure-${VM_NAME}"
SCRIPT_NAME=$(echo "$SCRIPT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')

# Generate the start script
SCRIPT_PATH="$LOCAL_BIN/$SCRIPT_NAME"
cat > "$SCRIPT_PATH" << STARTSCRIPT
#!/usr/bin/env bash
# Start and connect to Azure VM: ${VM_NAME}
set -euo pipefail

RG="${RG}"
VM_NAME="${VM_NAME}"
SSH_KEY="${SSH_KEY}"
SSH_USER="${SSH_USER}"

echo "Checking VM state..."
STATE=\$(az vm get-instance-view --resource-group "\$RG" --name "\$VM_NAME" \
  --query 'instanceView.statuses[1].displayStatus' -o tsv 2>/dev/null)

if [[ "\$STATE" == *"deallocated"* ]] || [[ "\$STATE" == *"stopped"* ]]; then
  echo "Starting VM \$VM_NAME..."
  az vm start --resource-group "\$RG" --name "\$VM_NAME"
elif [[ "\$STATE" == *"running"* ]]; then
  echo "VM already running."
else
  echo "VM is in state: \$STATE"
  exit 1
fi

IP=\$(az vm show --resource-group "\$RG" --name "\$VM_NAME" --show-details \
  --query publicIps -o tsv)
echo "Public IP: \$IP"

echo "Connecting via SSH..."
ssh -i "\$SSH_KEY" -o StrictHostKeyChecking=accept-new "\$SSH_USER@\$IP"
STARTSCRIPT

chmod +x "$SCRIPT_PATH"

echo -e "\n${GREEN}Start script created: ${SCRIPT_PATH}${NC}"
echo -e "Run it with: ${BLUE}${SCRIPT_NAME}${NC}"
echo -e "\nMake sure ${LOCAL_BIN} is in your PATH:"
echo -e '  export PATH="$HOME/.local/bin:$PATH"'
