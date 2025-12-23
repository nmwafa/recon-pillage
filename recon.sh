#!/bin/bash

# ============================================================
#  What is this: Automated Recon & Pillage v1.7
#  Description : Performs subdomain enumeration, http probing,
#                and categorization based on status codes.
#
#  Changes     : Removed redundant sorting phase.
#                Added regex filtering for colored status codes.
# ============================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Input Validation & Directory Setup
if [ -z "$1" ]; then
    echo -e "${RED}[!] Usage: ./recon.sh <domain> [output_directory]${NC}"
    echo -e "${YELLOW}[*] Example: ./recon.sh evil.com ./results/bugbounty${NC}"
    exit 1
fi

DOMAIN=$1
OUTPUT_DIR="${2:-.}"
OUTPUT_DIR="${OUTPUT_DIR%/}"
BASENAME=$(echo $DOMAIN | cut -d. -f1)

# Ensure Output Directory Exists
if [ ! -d "$OUTPUT_DIR" ]; then
    echo -e "${YELLOW}[*] Directory '$OUTPUT_DIR' does not exist. Creating it...${NC}"
    mkdir -p "$OUTPUT_DIR"
fi

# Define file paths
SUBS_LIST="${OUTPUT_DIR}/${BASENAME}.txt"
HTTPX_OUT="${OUTPUT_DIR}/${BASENAME}.httpx"

echo -e "${GREEN}[+] Target: ${DOMAIN}${NC}"
echo -e "${GREEN}[+] Output Directory: ${OUTPUT_DIR}${NC}"

# ============================================================
#  Subdomain Enumeration (Direct to Clean List)
# ============================================================
echo -e "${YELLOW}[*] Phase 1: Enumerating subdomains...${NC}"

# Initialize empty file if not exists (or clear it if you want fresh start)
# rm -f "$SUBS_LIST" # Uncomment to force fresh start every time
touch "$SUBS_LIST"

# Subfinder
if command -v subfinder &> /dev/null; then
    echo "    [i] Running Subfinder..."
    subfinder -d "$DOMAIN" -o "$SUBS_LIST" &> /dev/null
else
    echo -e "${RED}[!] Subfinder not found. Skipping.${NC}"
fi

# Passive sources
echo "    [i] Retrieve subdomains from otx.alienvault.com..."
curl -s "https://otx.alienvault.com/api/v1/indicators/hostname/$DOMAIN/passive_dns" | jq -r '.passive_dns[]?.hostname' | grep -E "^[a-zA-Z0-9.-]+\.$DOMAIN$" | anew "$SUBS_LIST" &> /dev/null

echo "    [i] Retrieve subdomains from urlscan.io..."
curl -s "https://urlscan.io/api/v1/search/?q=domain:$DOMAIN&size=10000" | jq -r '.results[]?.page?.domain' | grep -E "^[a-zA-Z0-9.-]+\.$DOMAIN$" | anew "$SUBS_LIST" &> /dev/null

echo "    [i] Retrieve subdomains from crt.sh..."
curl -s "https://crt.sh/json?q=$DOMAIN" | jq -r '.[].name_value' 2> /dev/null | grep -E "^[a-zA-Z0-9.-]+\.$DOMAIN$" | anew "$SUBS_LIST" &> /dev/null

# Cek apakah subdomains ditemukan
if [ ! -s "$SUBS_LIST" ]; then
    echo -e "${RED}[!] No subdomains found. Exiting.${NC}"
    exit 1
else
    COUNT=$(wc -l < "$SUBS_LIST")
    echo -e "${GREEN}[+] Total unique subdomains found: ${COUNT}${NC}"
fi

# ============================================================
#  HTTP Probing (httpx)
# ============================================================
echo -e "${YELLOW}[*] Phase 2: Probing with httpx...${NC}"

echo "    [i] Running httpx..."
httpx-toolkit -l "$SUBS_LIST" -sc -title -td -o "$HTTPX_OUT" &> /dev/null

if [ ! -s "$HTTPX_OUT" ]; then
    echo -e "${RED}[!] httpx generated no output. Exiting.${NC}"
    exit 1
fi

# ============================================================
#  Filtering and Pillaging (Categorization)
# ============================================================
echo -e "${YELLOW}[*] Phase 3: Categorizing and filtering results...${NC}"

filter_data() {
    KEYWORD=$1
    CLEAN_KEY="${KEYWORD//[^a-zA-Z0-9]/}"
    OUTFILE="${OUTPUT_DIR}/${BASENAME}.${CLEAN_KEY}"
    
    # Special Regex for Status Code
    if [[ "$KEYWORD" =~ ^[0-9]{3}$ ]]; then
        grep -P "\[\x1b\[[0-9;]*m${KEYWORD}\x1b\[0m\]" "$HTTPX_OUT" > "$OUTFILE"
    elif [[ "$KEYWORD" == "api" ]]; then
        cut -d' ' -f1 "$HTTPX_OUT" | grep -i "api" > "$OUTFILE"
    else
        grep -i "$KEYWORD" "$HTTPX_OUT" > "$OUTFILE"
    fi

    if [ ! -s "$OUTFILE" ]; then
        rm "$OUTFILE"
    else
        MATCH_COUNT=$(wc -l < "$OUTFILE")
        echo -e "    [+] Filter '${GREEN}${KEYWORD}${NC}': Found ${MATCH_COUNT} -> ${OUTFILE}"
    fi
}

echo "    [i] Processing Status Codes..."
filter_data "200"
filter_data "301"
filter_data "302"
filter_data "401"
filter_data "403"
filter_data "404"
filter_data "500"

echo "    [i] Processing Technologies & Keywords..."
KEYWORDS=(
    "wordpress"
    "drupal"
    "joomla"
    "login"
    "api"
    "admin"
    "test"
    "dev"
    "staging"
    "php"
    "laravel"
    "tomcat"
    "jenkins"
    "git"
    "gitlab"
)

for KEY in "${KEYWORDS[@]}"; do
    filter_data "$KEY"
done

echo -e "${GREEN}[+] Automation Complete! Results are in: ${OUTPUT_DIR}${NC}"
