#!/usr/bin/env bash
# =============================================================================
# Azure VM Auto-Shutdown - Deployment Script
# =============================================================================
# This script deploys the VM auto-shutdown infrastructure to Azure.
#
# Prerequisites:
#   - Azure CLI installed (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
#   - Bicep CLI installed (az bicep install)
#   - Logged in to Azure (az login)
#   - SSH key pair generated
#
# Usage:
#   ./deploy.sh                    # Deploy with defaults
#   ./deploy.sh --validate         # Validate only (no deployment)
#   ./deploy.sh --what-if          # Preview changes (no deployment)
#   ./deploy.sh --delete           # Delete the resource group
# =============================================================================

set -euo pipefail

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-autoshutdown-rg}"
LOCATION="${LOCATION:-southeastasia}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/azure-autoshutdown.pub}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
DEFAULT_SSH_CIDR="127.0.0.1/32"
if command -v curl &> /dev/null; then
    DETECTED_IP="$(curl -fsS https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$DETECTED_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        DEFAULT_SSH_CIDR="${DETECTED_IP}/32"
    fi
fi
ALLOWED_SSH_CIDR="${ALLOWED_SSH_CIDR:-$DEFAULT_SSH_CIDR}"
DEPLOYMENT_NAME="autoshutdown-$(date +%Y%m%d-%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Pre-flight Checks
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    log_ok "Azure CLI: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null)"

    # Check Bicep
    if ! az bicep version &> /dev/null; then
        log_warn "Bicep CLI not found. Installing..."
        az bicep install
    fi
    log_ok "Bicep CLI: $(az bicep version 2>&1 | head -1)"

    # Check login
    if ! az account show &> /dev/null; then
        log_error "Not logged in. Run: az login"
        exit 1
    fi
    local ACCOUNT=$(az account show --query '{name:name, id:id}' -o tsv 2>/dev/null)
    log_ok "Azure account: $ACCOUNT"

    # Check/generate SSH key
    if [ ! -f "$SSH_KEY_PATH" ]; then
        local PRIVATE_KEY="${SSH_KEY_PATH%.pub}"
        log_warn "SSH key not found at $SSH_KEY_PATH"
        log_info "Generating ED25519 SSH key pair..."
        ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -C "azure-autoshutdown"
        log_ok "SSH key pair generated: $PRIVATE_KEY"
    fi
    log_ok "SSH public key: $SSH_KEY_PATH"
}

# =============================================================================
# Validate Bicep Templates
# =============================================================================
validate() {
    log_info "Validating Bicep templates..."

    # Build (syntax check)
    if az bicep build --file main.bicep --stdout > /dev/null 2>&1; then
        log_ok "Bicep syntax validation passed"
    else
        log_error "Bicep syntax validation failed:"
        az bicep build --file main.bicep 2>&1
        exit 1
    fi

    # Validate against Azure (requires resource group)
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        local SSH_KEY=$(cat "$SSH_KEY_PATH")
        if az deployment group validate \
            --resource-group "$RESOURCE_GROUP" \
            --template-file main.bicep \
            --parameters \
                sshPublicKey="$SSH_KEY" \
                location="$LOCATION" \
                vmSize="$VM_SIZE" \
                allowedSshCidr="$ALLOWED_SSH_CIDR" \
            --no-prompt &> /dev/null; then
            log_ok "Azure deployment validation passed"
        else
            log_warn "Azure deployment validation failed (resource group may not exist yet)"
            az deployment group validate \
                --resource-group "$RESOURCE_GROUP" \
                --template-file main.bicep \
                --parameters \
                    sshPublicKey="$SSH_KEY" \
                    location="$LOCATION" \
                    vmSize="$VM_SIZE" \
                    allowedSshCidr="$ALLOWED_SSH_CIDR" 2>&1
        fi
    else
        log_warn "Resource group '$RESOURCE_GROUP' does not exist. Skipping deployment validation."
    fi
}

# =============================================================================
# What-If Preview
# =============================================================================
what_if() {
    log_info "Running what-if deployment preview..."

    # Create resource group if needed
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none 2>/dev/null || true

    local SSH_KEY=$(cat "$SSH_KEY_PATH")
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters \
            sshPublicKey="$SSH_KEY" \
            location="$LOCATION" \
            vmSize="$VM_SIZE" \
            allowedSshCidr="$ALLOWED_SSH_CIDR"
}

# =============================================================================
# Deploy
# =============================================================================
deploy() {
    log_info "Deploying Azure VM Auto-Shutdown infrastructure..."
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location:       $LOCATION"
    echo "  VM Size:        $VM_SIZE"
    echo "  SSH CIDR:       $ALLOWED_SSH_CIDR"
    echo "  SSH Key:        $SSH_KEY_PATH"
    echo "  Deployment:     $DEPLOYMENT_NAME"
    echo ""

    # Create resource group
    log_info "Creating resource group '$RESOURCE_GROUP'..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    log_ok "Resource group created"

    # Deploy
    local SSH_KEY=$(cat "$SSH_KEY_PATH")
    log_info "Deploying Bicep template (this may take 2-5 minutes)..."
    local OUTPUT
    if ! OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --name "$DEPLOYMENT_NAME" \
        --parameters \
            sshPublicKey="$SSH_KEY" \
            location="$LOCATION" \
            vmSize="$VM_SIZE" \
            allowedSshCidr="$ALLOWED_SSH_CIDR" \
        --query 'properties.outputs' \
        --output json 2>&1); then

        log_error "Deployment failed!"
        echo "$OUTPUT" >&2

        # Detect SKU availability errors and suggest alternatives
        if echo "$OUTPUT" | grep -q "SkuNotAvailable"; then
            echo ""
            log_warn "VM size '$VM_SIZE' is not available in '$LOCATION'."
            log_info "Finding available sizes..."
            echo ""
            az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
                --size Standard_B2 --output table 2>/dev/null | grep -v "NotAvailableForSubscription" || true
            az vm list-skus --location "$LOCATION" --resource-type virtualMachines \
                --size Standard_D2 --output table 2>/dev/null | grep -v "NotAvailableForSubscription" | grep -v "ResourceType" || true
            echo ""
            log_info "Retry with: VM_SIZE=<available_size> ./deploy.sh"
        fi
        exit 1
    fi

    log_ok "Deployment complete!"
    echo ""
    echo "============================================================"
    echo "  Deployment Outputs"
    echo "============================================================"
    echo "$OUTPUT" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
    echo "============================================================"
    echo ""

    local PUBLIC_IP=$(echo "$OUTPUT" | jq -r '.publicIpAddress.value')
    local VM_NAME=$(echo "$OUTPUT" | jq -r '.vmName.value')

    echo "To connect:"
    echo "  ssh -i ${SSH_KEY_PATH%.pub} azureuser@${PUBLIC_IP}"
    echo ""
    echo "To check auto-shutdown logs (after connecting):"
    echo "  tail -f /var/log/autoshutdown.log"
    echo ""
    echo "To restart after auto-shutdown:"
    echo "  az vm start --resource-group $RESOURCE_GROUP --name $VM_NAME"
}

# =============================================================================
# Delete
# =============================================================================
delete() {
    log_warn "This will delete the entire resource group '$RESOURCE_GROUP' and all resources in it."
    read -p "Are you sure? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        log_info "Deleting resource group '$RESOURCE_GROUP'..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        log_ok "Resource group deletion initiated (running in background)"
    else
        log_info "Cancelled."
    fi
}

# =============================================================================
# Main
# =============================================================================
case "${1:-deploy}" in
    --validate|-v)
        check_prerequisites
        validate
        ;;
    --what-if|-w)
        check_prerequisites
        what_if
        ;;
    --delete|-d)
        delete
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  (no args)      Deploy the infrastructure"
        echo "  --validate     Validate Bicep templates only"
        echo "  --what-if      Preview deployment changes"
        echo "  --delete       Delete the resource group"
        echo "  --help         Show this help"
        echo ""
        echo "Environment variables:"
        echo "  RESOURCE_GROUP  Resource group name (default: autoshutdown-rg)"
        echo "  LOCATION        Azure region (default: southeastasia)"
        echo "  VM_SIZE         VM size (default: Standard_B2s)"
        echo "  ALLOWED_SSH_CIDR SSH ingress CIDR (default: auto-detected public IP/32)"
        echo "  SSH_KEY_PATH    Path to SSH public key (default: ~/.ssh/azure-autoshutdown.pub)"
        ;;
    *)
        check_prerequisites
        validate
        deploy
        ;;
esac
