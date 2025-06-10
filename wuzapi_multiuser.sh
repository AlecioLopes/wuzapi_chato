#!/data/data/com.termux/files/usr/bin/bash

# Script para instalar e gerenciar múltiplas instâncias do WuzAPI

# Configurações dos usuários
declare -A USERS=(
    ["7774"]="8080"  # USER_TOKEN=7774, PORT=8080
    ["7775"]="8081"  # USER_TOKEN=7775, PORT=8081
)

# Configurações comuns
ADMIN_TOKEN="3129"
WEBHOOK_URL="http://localhost:3129/tasker"
TMP_DIR="$HOME/wuzapi/tmp"
REPO_URL="https://github.com/WUZAPI-CHAT-BOT/WUZAPI-CHAT-BOT.git"
LOG_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/logs/multiuser.log"

# Cores ANSI
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ASCII Art
ASCII_ART="${BLUE}
╦ ╦╔═╗╦  ╔═╗╔═╗╦╔═
║║║║╣ ║  ║ ║║ ║╠╩╗
╚╩╝╚═╝╩═╝╚═╝╚═╝╩ ╩
${NC}"

# Configurar logs
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" || { echo -e "${RED}Erro ao criar arquivo de log${NC}"; exit 1; }

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log_header() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${ASCII_ART}\n$@" | tee -a "$LOG_FILE"
}

check_error() {
    if [ $? -ne 0 ]; then
        log "${RED}Erro: $1${NC}"
        exit 1
    fi
}

# Funções para gerenciar instâncias
start_instance() {
    local user_token=$1
    local port=$2
    local instance_dir="$HOME/wuzapi_$user_token"
    
    log "${YELLOW}Iniciando instância para usuário $user_token na porta $port${NC}"
    
    # Configurar e iniciar instância
    cd "$instance_dir" || return 1
    
    # Criar .env específico
    cat << EOF > .env
WUZAPI_ADMIN_TOKEN=$ADMIN_TOKEN
TZ=America/Sao_Paulo
SESSION_DEVICE_NAME=WuzAPI_$user_token
EOF
    
    # Liberar porta
    kill $(lsof -t -i:$port) 2>/dev/null
    
    # Iniciar WuzAPI
    ./wuzapi -logtype=json -color=true -port=$port &
    local pid=$!
    
    sleep 10
    
    # Criar usuário
    curl -X POST "http://localhost:$port/admin/users" \
    -H "Authorization: $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"user_'$user_token'","token":"'$user_token'","events":"All","webhook":"'$WEBHOOK_URL'"}' \
    && log "${GREEN}Usuário $user_token configurado com sucesso${NC}" \
    || log "${RED}Erro ao configurar usuário $user_token${NC}"
    
    echo "$pid"
}

check_connection() {
    local user_token=$1
    local port=$2
    local response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/login?token=$user_token" --connect-timeout 10)
    [ "$response" -eq 200 ]
}

monitor_instances() {
    declare -A pids
    local check_interval=300  # 5 minutos
    
    while true; do
        for user_token in "${!USERS[@]}"; do
            local port="${USERS[$user_token]}"
            local instance_dir="$HOME/wuzapi_$user_token"
            
            if ! check_connection "$user_token" "$port"; then
                log "${YELLOW}Reconectando usuário $user_token...${NC}"
                [ -n "${pids[$user_token]}" ] && kill "${pids[$user_token]}" 2>/dev/null
                pids[$user_token]=$(start_instance "$user_token" "$port")
            fi
        done
        sleep $check_interval
    done
}

# Instalação inicial
initialize_installation() {
    log_header "${BLUE}Iniciando instalação para múltiplos usuários${NC}"
    
    # 1. Configurar ambiente
    termux-setup-storage
    sleep 5
    
    # 2. Atualizar pacotes
    log "${YELLOW}Atualizando pacotes...${NC}"
    pkg update -y && pkg upgrade -y
    check_error "Falha ao atualizar pacotes"
    
    # 3. Instalar dependências
    log "${YELLOW}Instalando dependências...${NC}"
    pkg install -y golang git lsof psmisc
    check_error "Falha ao instalar dependências"
    
    # 4. Configurar Go
    export GO111MODULE=on
    export GOPATH="$HOME/go"
    
    # 5. Clonar repositório para cada usuário
    for user_token in "${!USERS[@]}"; do
        local instance_dir="$HOME/wuzapi_$user_token"
        
        log "${YELLOW}Configurando instância para $user_token...${NC}"
        
        # Clonar repositório
        [ -d "$instance_dir" ] && rm -rf "$instance_dir"
        git clone "$REPO_URL" "$instance_dir"
        check_error "Falha ao clonar para $user_token"
        
        # Instalar dependências
        cd "$instance_dir"
        go get -u go.mau.fi/whatsmeow@latest
        go mod tidy
        
        # Compilar
        go build .
        check_error "Falha ao compilar para $user_token"
    done
}

# Execução principal
main() {
    initialize_installation
    
    # Iniciar todas as instâncias
    declare -A instance_pids
    for user_token in "${!USERS[@]}"; do
        instance_pids[$user_token]=$(start_instance "$user_token" "${USERS[$user_token]}")
        log "${GREEN}Instância $user_token iniciada com PID ${instance_pids[$user_token]}${NC}"
    done
    
    # Iniciar monitoramento
    monitor_instances &
    
    log_header "${GREEN}Todas instâncias iniciadas com sucesso!${NC}"
    log "${BLUE}Usuários configurados:${NC}"
    for user_token in "${!USERS[@]}"; do
        log "• Usuário: ${GREEN}$user_token${NC} | Porta: ${BLUE}${USERS[$user_token]}${NC} | PID: ${YELLOW}${instance_pids[$user_token]}${NC}"
        log "  URL: http://localhost:${USERS[$user_token]}/login?token=$user_token"
    done
    
    wait
}

main
