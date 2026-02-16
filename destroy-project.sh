#!/usr/bin/env bash
# Azure Resource Group Destroyer
# Safely destroys Azure resource groups with confirmation.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}Azure Resource Group Destroyer${NC}\n"

# Check prerequisites
command -v az &>/dev/null || { echo -e "${RED}Error: Azure CLI not installed${NC}"; exit 1; }
az account show &>/dev/null || { echo -e "${RED}Error: Not authenticated. Run: az login${NC}"; exit 1; }

# List resource groups
echo -e "${BLUE}Resource groups:${NC}"
az group list --query '[].{Name:name,Location:location,State:properties.provisioningState}' --output table

echo ""
read -p "Resource group to destroy: " RG
[ -z "$RG" ] && { echo -e "${RED}No resource group provided${NC}"; exit 1; }

# Show resources in the group
echo -e "\n${BLUE}Resources in ${RG}:${NC}"
az resource list --resource-group "$RG" --query '[].{Name:name,Type:type}' --output table 2>/dev/null

echo -e "\n${YELLOW}WARNING: This will permanently delete resource group '${RG}' and ALL resources in it.${NC}"
read -p "Type the resource group name to confirm: " CONFIRM
[ "$CONFIRM" != "$RG" ] && { echo -e "${RED}Confirmation failed. Aborting.${NC}"; exit 1; }

echo -e "\n${BLUE}Deleting resource group ${RG}...${NC}"
az group delete --name "$RG" --yes

echo -e "\n${GREEN}Resource group ${RG} deleted successfully.${NC}"
