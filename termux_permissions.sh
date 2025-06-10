#!/bin/bash

# Script para gerenciar permissões do Termux (igual ao anterior)

LOG_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/logs/termux-permission.log"
LOG_DIR=$(dirname "$LOG_FILE")

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p "$LOG_DIR"
touch "$LOG_FILE" || { echo -e "${RED}Erro ao criar arquivo de log${NC}"; exit 1; }

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log "${GREEN}Iniciando script de permissões...${NC}"

mkdir -p ~/.termux
if ! grep -q "allow-external-apps=true" ~/.termux/termux.properties; then
    echo "allow-external-apps=true" >> ~/.termux/termux.properties
    log "Configurado allow-external-apps=true"
fi

while true; do
    if [ -d "/storage/emulated/0" ] && [ -d "/data/data/com.termux/files/home/storage" ]; then
        log "${GREEN}Permissões OK${NC}"
    else
        log "${RED}Permissões faltando. Solicitando...${NC}"
        termux-setup-storage
        pkill -TERM termux
        sleep 10
    fi
    sleep 60
done
