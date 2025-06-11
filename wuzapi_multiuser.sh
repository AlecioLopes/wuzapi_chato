#!/data/data/com.termux/files/usr/bin/bash

# Script definitivo para instalação do WuzAPI com múltiplos usuários

# Configurações principais
ADMIN_TOKEN="3129"
declare -A USERS=(
    ["7774"]="8080"  # Token: 7774, Porta: 8080
    ["7775"]="8081"  # Token: 7775, Porta: 8081
)
REPO_URL="https://github.com/WUZAPI-CHAT-BOT/WUZAPI-CHAT-BOT.git"
LOG_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/logs/wuzapi_final.log"

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variáveis globais
declare -A INSTANCE_PIDS
declare -A INSTANCE_DIRS

# Função para registrar logs
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

# Função para mostrar status
show_step() {
    echo -e "${YELLOW}\n▶ ETAPA $1: $2${NC}"
    log "▶ ETAPA $1: $2"
}

# Função para mostrar sucesso
show_success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "✓ $1"
}

# Função para mostrar erro
show_error() {
    echo -e "${RED}✗ ERRO: $1${NC}"
    log "✗ ERRO: $1"
    [ "$2" == "fatal" ] && exit 1
}

# Configurar ambiente
setup_environment() {
    show_step 1 "Configurando ambiente Termux"
    
    # Criar diretório de logs
    mkdir -p "$(dirname "$LOG_FILE")" || show_error "Falha ao criar diretório de logs" "fatal"
    touch "$LOG_FILE" || show_error "Não foi possível criar arquivo de log" "fatal"
    
    # Configurar permissões
    termux-setup-storage
    sleep 5
    
    if [ ! -d "/storage/emulated/0" ]; then
        show_error "Falha ao obter permissões de armazenamento" "fatal"
    fi
    
    # Permitir apps externos
    mkdir -p ~/.termux
    echo "allow-external-apps=true" > ~/.termux/termux.properties
    pkill -TERM com.termux >/dev/null 2>&1
    sleep 2
    show_success "Ambiente configurado com sucesso"
}

# Instalar dependências
install_dependencies() {
    show_step 2 "Instalando dependências"
    
    echo -e "${CYAN}Atualizando pacotes...${NC}"
    pkg update -y && pkg upgrade -y || show_error "Falha ao atualizar pacotes" "fatal"
    
    echo -e "${CYAN}Instalando Go, Git e ferramentas...${NC}"
    pkg install -y golang git lsof psmisc || show_error "Falha ao instalar dependências" "fatal"
    
    if ! go version >/dev/null 2>&1; then
        show_error "Go não está instalado corretamente" "fatal"
    fi
    
    show_success "Todas dependências instaladas com sucesso"
}

# Preparar instâncias
prepare_instances() {
    show_step 3 "Preparando instâncias"
    
    export GO111MODULE=on
    export GOPATH="$HOME/go"
    
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        INSTANCE_DIR="$HOME/wuzapi_$USER_TOKEN"
        INSTANCE_DIRS["$USER_TOKEN"]="$INSTANCE_DIR"
        
        echo -e "${CYAN}\n● Preparando usuário $USER_TOKEN na porta $PORT${NC}"
        
        # Clonar ou atualizar repositório
        if [ -d "$INSTANCE_DIR" ]; then
            echo -e "${YELLOW}Diretório existente encontrado. Atualizando...${NC}"
            cd "$INSTANCE_DIR" || show_error "Falha ao acessar diretório" "continue"
            git pull origin main || show_error "Falha ao atualizar repositório" "continue"
        else
            echo "Clonando repositório..."
            git clone "$REPO_URL" "$INSTANCE_DIR" || show_error "Falha ao clonar repositório" "continue"
        fi
        
        cd "$INSTANCE_DIR" || show_error "Falha ao acessar diretório da instância" "continue"
        
        # Instalar dependências do Go
        echo "Instalando dependências..."
        go get -u go.mau.fi/whatsmeow@latest
        go mod tidy
        
        # Compilar
        echo "Compilando WuzAPI..."
        go build . || show_error "Falha ao compilar WuzAPI" "continue"
        
        # Criar arquivo de configuração
        cat << EOF > .env
WUZAPI_ADMIN_TOKEN=$ADMIN_TOKEN
TZ=America/Sao_Paulo
SESSION_DEVICE_NAME=WuzAPI_$USER_TOKEN
EOF
        
        show_success "Instância $USER_TOKEN preparada com sucesso"
    done
}

# Iniciar instâncias
start_instances() {
    show_step 4 "Iniciando todas as instâncias"
    
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        INSTANCE_DIR="${INSTANCE_DIRS[$USER_TOKEN]}"
        
        echo -e "${CYAN}\n● Iniciando usuário $USER_TOKEN na porta $PORT${NC}"
        
        cd "$INSTANCE_DIR" || show_error "Falha ao acessar diretório da instância" "continue"
        
        # Liberar porta
        PORT_PROCESS=$(lsof -t -i:$PORT)
        if [ -n "$PORT_PROCESS" ]; then
            echo -e "${YELLOW}Liberando porta $PORT (processo $PORT_PROCESS)${NC}"
            kill -9 $PORT_PROCESS 2>/dev/null
            sleep 2
        fi
        
        # Iniciar instância
        echo "Iniciando WuzAPI..."
        nohup ./wuzapi -logtype=json -color=true -port=$PORT > "$INSTANCE_DIR/wuzapi.log" 2>&1 &
        INSTANCE_PIDS["$USER_TOKEN"]=$!
        sleep 15
        
        # Verificar se está rodando
        if ps -p ${INSTANCE_PIDS["$USER_TOKEN"]} > /dev/null; then
            show_success "Instância $USER_TOKEN iniciada com PID ${INSTANCE_PIDS["$USER_TOKEN"]}"
        else
            show_error "Falha ao iniciar instância $USER_TOKEN" "continue"
        fi
        
        # Criar usuário
        echo "Registrando usuário..."
        curl -X POST "http://localhost:$PORT/admin/users" \
        -H "Authorization: $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name":"user_'$USER_TOKEN'","token":"'$USER_TOKEN'","events":"All","webhook":""}' \
        && show_success "Usuário $USER_TOKEN registrado com sucesso" \
        || show_error "Falha ao registrar usuário $USER_TOKEN" "continue"
    done
}

# Verificar instâncias
verify_instances() {
    show_step 5 "Verificando todas as instâncias"
    
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        
        echo -e "${CYAN}\n● Verificando usuário $USER_TOKEN na porta $PORT${NC}"
        
        # Verificar processo
        if ! ps -p ${INSTANCE_PIDS["$USER_TOKEN"]} > /dev/null; then
            show_error "Processo da instância $USER_TOKEN não está rodando" "continue"
        fi
        
        # Verificar conexão HTTP
        echo "Testando conexão..."
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/login?token=$USER_TOKEN" --connect-timeout 10)
        
        if [ "$RESPONSE" -eq 200 ]; then
            show_success "Conexão do usuário $USER_TOKEN está ativa (HTTP 200)"
            echo -e "${GREEN}URL para pareamento: http://localhost:$PORT/login?token=$USER_TOKEN${NC}"
        else
            show_error "Falha na conexão do usuário $USER_TOKEN (HTTP $RESPONSE)" "continue"
        fi
    done
}

# Mostrar instruções finais
show_final_instructions() {
    echo -e "${GREEN}\n\n======================================================"
    echo "         INSTALAÇÃO CONCLUÍDA COM SUCESSO!          "
    echo "======================================================"
    echo -e "${YELLOW}\nPARA CONECTAR SEUS NÚMEROS:${NC}\n"
    
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        echo -e "${CYAN}● NÚMERO COM TOKEN ${YELLOW}$USER_TOKEN${CYAN}:${NC}"
        echo "  1. Abra no navegador:"
        echo -e "     ${BLUE}http://localhost:$PORT/login?token=$USER_TOKEN${NC}"
        echo "  2. Escaneie o QR code com o WhatsApp correspondente"
        echo ""
    done
    
    echo -e "${GREEN}======================================================"
    echo -e "${YELLOW}INFORMAÇÕES IMPORTANTES:${NC}"
    echo "1. Mantenha o Termux aberto em segundo plano"
    echo "2. Não feche esta sessão do Termux"
    echo "3. Logs completos em:"
    echo -e "   ${BLUE}$LOG_FILE${NC}"
    echo -e "4. Logs individuais em:"
    for USER_TOKEN in "${!USERS[@]}"; do
        echo -e "   ${BLUE}${INSTANCE_DIRS[$USER_TOKEN]}/wuzapi.log${NC}"
    done
    echo -e "${GREEN}======================================================"
    echo -e "       AMBAS INSTÂNCIAS ESTÃO PRONTAS PARA PAREMETO!      "
    echo -e "======================================================${NC}"
    
    # Comando para manter o script rodando
    while true; do sleep 3600; done
}

# Fluxo principal
main() {
    clear
    echo -e "${GREEN}Iniciando instalação do WuzAPI para múltiplos usuários...${NC}"
    
    setup_environment
    install_dependencies
    prepare_instances
    start_instances
    verify_instances
    show_final_instructions
}

main
