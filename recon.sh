#!/bin/bash

# ============================================================
#  What is this: Automated Recon & Pillage v1
#  Description : Performs subdomain enumeration, cleaning,
#                http probing, and categorization based on
#                status codes and technologies.
#
# Vibe coded by: https://nmwafa.github.io
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
# Set output directory to argument 2, or default to "." (current dir)
OUTPUT_DIR="${2:-.}"

# Remove trailing slash from directory path if present for consistency
OUTPUT_DIR="${OUTPUT_DIR%/}"

# Extract basename (e.g., evil.com -> evil)
BASENAME=$(echo $DOMAIN | cut -d. -f1)

# Ensure Output Directory Exists
if [ ! -d "$OUTPUT_DIR" ]; then
    echo -e "${YELLOW}[*] Directory '$OUTPUT_DIR' does not exist. Creating it...${NC}"
    mkdir -p "$OUTPUT_DIR"
fi

# Define file paths
RAW_FILE="${OUTPUT_DIR}/raw_subs.txt"
MAIN_LIST="${OUTPUT_DIR}/${BASENAME}"
HTTPX_OUT="${OUTPUT_DIR}/${BASENAME}.httpx"

echo -e "${GREEN}[+] Target: ${DOMAIN}${NC}"
echo -e "${GREEN}[+] Output Directory: ${OUTPUT_DIR}${NC}"

# ============================================================
#  Subdomain Enumeration
# ============================================================
echo -e "${YELLOW}[*] Phase 1: Enumerating subdomains...${NC}"

# Clear previous raw file if exists to avoid appending old data
rm -f "$RAW_FILE"

# Tool 1: Subfinder
if command -v subfinder &> /dev/null; then
    echo "    [i] Running Subfinder..."
    subfinder -d "$DOMAIN" -silent >> "$RAW_FILE"
else
    echo -e "${RED}[!] Subfinder not found. Skipping.${NC}"
fi

# Tool 2: Assetfinder (Optional)
if command -v assetfinder &> /dev/null; then
    echo "    [i] Running Assetfinder..."
    assetfinder --subs-only "$DOMAIN" >> "$RAW_FILE"
fi

# You can add extra subdomain search tools here...

# ============================================================
#  Sorting and Cleaning
# ============================================================
echo -e "${YELLOW}[*] Phase 2: Sorting and removing duplicates...${NC}"

if [ -s "$RAW_FILE" ]; then
    # Sort, unique, and save to the MAIN_LIST path
    sort -u "$RAW_FILE" > "$MAIN_LIST"

    COUNT=$(wc -l < "$MAIN_LIST")
    echo -e "${GREEN}[+] Clean list saved to: ${MAIN_LIST} (Total: ${COUNT})${NC}"

    # Cleanup raw file
    rm "$RAW_FILE"
else
    echo -e "${RED}[!] No subdomains found in Phase 1. Exiting.${NC}"
    rm -f "$RAW_FILE"
    exit 1
fi

# ============================================================
#  HTTP Probing (httpx)
# ============================================================
echo -e "${YELLOW}[*] Phase 3: Probing with httpx...${NC}"

# Running httpx-toolkit with title, status code, and technology detection
# if using httpx without -toolkit, just change it
echo "    [i] Running httpx..."
httpx-toolkit -l "$MAIN_LIST" -sc -title -td -o "$HTTPX_OUT" &> /dev/null

if [ ! -s "$HTTPX_OUT" ]; then
    echo -e "${RED}[!] httpx generated no output. Exiting.${NC}"
    exit 1
fi

# ============================================================
#  Filtering and Pillaging (Categorization)
# ============================================================
echo -e "${YELLOW}[*] Phase 4: Categorizing and filtering results...${NC}"

# Function to grep, save, and remove if empty
filter_data() {
    KEYWORD=$1
    CLEAN_KEY="${KEYWORD//[^a-zA-Z0-9]/}"

    # Define specific output file path
    OUTFILE="${OUTPUT_DIR}/${BASENAME}.${CLEAN_KEY}"

    # Perform the grep (Case insensitive)
    if [[ "$KEYWORD" == "api" ]]; then
        cut -d' ' -f1 "$HTTPX_OUT" | grep -i "api" > "$OUTFILE"
    else
        grep -i "$KEYWORD" "$HTTPX_OUT" > "$OUTFILE"
    fi
    # Check if file is empty
    if [ ! -s "$OUTFILE" ]; then
        rm "$OUTFILE"
    else
        MATCH_COUNT=$(wc -l < "$OUTFILE")
        echo -e "    [+] Filter '${GREEN}${KEYWORD}${NC}': Found ${MATCH_COUNT} -> ${OUTFILE}"
    fi
}

echo "    [i] Processing Status Codes..."
# Using brackets to be precise with httpx output format
filter_data "200"
filter_data "301"
filter_data "302"
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
# Sometimes you might see false positives in code-based grouping. Sorry about that :)

echo -e "${GREEN}[+] Automation Complete! Results are in: ${OUTPUT_DIR}${NC}"