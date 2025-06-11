#!/data/data/com.termux/files/usr/bin/bash

# Script melhorado para instalação e execução do WuzAPI com múltiplos usuários
# Versão com separação de fases: Instalação -> Configuração -> Inicialização

# Configurações
ADMIN_TOKEN="3129"
declare -A USERS=(
    ["7774"]="8080"  # Token: 7774, Porta: 8080
    ["7775"]="8081"  # Token: 7775, Porta: 8081
)
REPO_URL="https://github.com/WUZAPI-CHAT-BOT/WUZAPI-CHAT-BOT.git"
LOG_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/logs/wuzapi_install.log"
CONTROL_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/wuzapi_control.txt"

# Cores para melhor visualização
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Função para registrar logs
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

# Função para mostrar status
show_step() {
    echo -e "${YELLOW}>> ETAPA $1: $2${NC}"
    log ">> ETAPA $1: $2"
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
}

# Função para mostrar aviso
show_warning() {
    echo -e "${PURPLE}⚠ $1${NC}"
    log "⚠ $1"
}

# Função para salvar status no arquivo de controle
save_status() {
    echo "$1" > "$CONTROL_FILE"
    log "Status salvo: $1"
}

# Função para ler status do arquivo de controle
read_status() {
    if [ -f "$CONTROL_FILE" ]; then
        cat "$CONTROL_FILE"
    else
        echo "NOT_STARTED"
    fi
}

# Configurar ambiente
setup_environment() {
    show_step 1 "Configurando ambiente Termux"
    
    # Criar diretórios necessários
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$CONTROL_FILE")"
    touch "$LOG_FILE" || show_error "Não foi possível criar arquivo de log"
    
    # Configurar permissões
    termux-setup-storage
    sleep 5
    
    if [ -d "/storage/emulated/0" ]; then
        show_success "Permissões de armazenamento concedidas"
    else
        show_error "Falha ao obter permissões de armazenamento"
        return 1
    fi
    
    # Permitir apps externos
    mkdir -p ~/.termux
    echo "allow-external-apps=true" > ~/.termux/termux.properties
    pkill -TERM com.termux >/dev/null 2>&1
    show_success "Apps externos permitidos"
    
    save_status "ENVIRONMENT_SETUP"
    return 0
}

# Instalar dependências
install_dependencies() {
    show_step 2 "Atualizando pacotes e instalando dependências"
    
    pkg update -y && pkg upgrade -y
    if [ $? -eq 0 ]; then
        show_success "Pacotes atualizados com sucesso"
    else
        show_error "Falha ao atualizar pacotes"
        return 1
    fi
    
    pkg install -y golang git lsof curl
    if [ $? -eq 0 ]; then
        show_success "Dependências instaladas: Golang, Git, lsof, curl"
    else
        show_error "Falha ao instalar dependências"
        return 1
    fi
    
    # Verificar instalação do Go
    if go version; then
        show_success "Go instalado corretamente"
    else
        show_error "Problema na instalação do Go"
        return 1
    fi
    
    save_status "DEPENDENCIES_INSTALLED"
    return 0
}

# Configurar instâncias (SEM INICIALIZAR)
setup_instances() {
    show_step 3 "Configurando instâncias para cada usuário (SEM INICIALIZAR)"
    
    export GO111MODULE=on
    export GOPATH="$HOME/go"
    
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        INSTANCE_DIR="$HOME/wuzapi_$USER_TOKEN"
        
        echo -e "${CYAN}\n=== CONFIGURANDO USUÁRIO $USER_TOKEN PARA PORTA $PORT ===${NC}"
        log "Configurando usuário $USER_TOKEN para porta $PORT"
        
        # Clonar repositório
        if [ -d "$INSTANCE_DIR" ]; then
            echo -e "${YELLOW}Diretório existente encontrado. Atualizando...${NC}"
            cd "$INSTANCE_DIR"
            git pull origin main
        else
            echo "Clonando repositório..."
            git clone "$REPO_URL" "$INSTANCE_DIR"
        fi
        
        if [ $? -ne 0 ]; then
            show_error "Falha ao clonar/atualizar repositório para $USER_TOKEN"
            return 1
        fi
        
        cd "$INSTANCE_DIR" || {
            show_error "Não foi possível acessar $INSTANCE_DIR"
            return 1
        }
        
        # Instalar dependências do Go
        echo "Instalando dependências do Go..."
        go get -u go.mau.fi/whatsmeow@latest
        go mod tidy
        
        # Compilar
        echo "Compilando WuzAPI..."
        go build .
        if [ $? -ne 0 ]; then
            show_error "Falha ao compilar para $USER_TOKEN"
            return 1
        fi
        
        # Criar arquivo de configuração
        cat << EOF > .env
WUZAPI_ADMIN_TOKEN=$ADMIN_TOKEN
TZ=America/Sao_Paulo
SESSION_DEVICE_NAME=WuzAPI_$USER_TOKEN
EOF
        
        # Criar script de inicialização individual
        cat << EOF > start_instance.sh
#!/data/data/com.termux/files/usr/bin/bash
cd "$INSTANCE_DIR"
echo "Iniciando instância $USER_TOKEN na porta $PORT..."
./wuzapi -logtype=json -color=true -port=$PORT
EOF
        chmod +x start_instance.sh
        
        show_success "Instância $USER_TOKEN configurada (PRONTA PARA INICIAR)"
    done
    
    save_status "INSTANCES_CONFIGURED"
    return 0
}

# Criar scripts de controle
create_control_scripts() {
    show_step 4 "Criando scripts de controle"
    
    # Script para iniciar todas as instâncias
    cat << 'EOF' > "$HOME/start_all_wuzapi.sh"
#!/data/data/com.termux/files/usr/bin/bash

# Configurações
ADMIN_TOKEN="3129"
declare -A USERS=(
    ["7774"]="8080"
    ["7775"]="8081"
)
CONTROL_FILE="/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/wuzapi_control.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}           INICIANDO TODAS AS INSTÂNCIAS              ${NC}"
echo -e "${GREEN}======================================================${NC}"

# Liberar portas ocupadas
for USER_TOKEN in "${!USERS[@]}"; do
    PORT="${USERS[$USER_TOKEN]}"
    PORT_PROCESS=$(lsof -t -i:$PORT 2>/dev/null)
    if [ -n "$PORT_PROCESS" ]; then
        echo -e "${YELLOW}Liberando porta $PORT (processo $PORT_PROCESS)${NC}"
        kill -9 $PORT_PROCESS
        sleep 2
    fi
done

# Iniciar instâncias
for USER_TOKEN in "${!USERS[@]}"; do
    PORT="${USERS[$USER_TOKEN]}"
    INSTANCE_DIR="$HOME/wuzapi_$USER_TOKEN"
    
    echo -e "${CYAN}Iniciando instância $USER_TOKEN na porta $PORT...${NC}"
    
    cd "$INSTANCE_DIR"
    ./wuzapi -logtype=json -color=true -port=$PORT &
    WUZAPI_PID=$!
    echo $WUZAPI_PID > "$HOME/wuzapi_${USER_TOKEN}.pid"
    
    sleep 5
    
    # Verificar se está rodando
    if ps -p $WUZAPI_PID > /dev/null; then
        echo -e "${GREEN}✓ Instância $USER_TOKEN iniciada com PID $WUZAPI_PID${NC}"
        
        # Criar usuário
        sleep 5
        echo "Criando usuário $USER_TOKEN..."
        curl -X POST "http://localhost:$PORT/admin/users" \
        -H "Authorization: $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name":"user_'$USER_TOKEN'","token":"'$USER_TOKEN'","events":"All","webhook":""}' \
        > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Usuário $USER_TOKEN criado${NC}"
        else
            echo -e "${YELLOW}⚠ Usuário $USER_TOKEN pode já existir${NC}"
        fi
        
    else
        echo -e "${RED}✗ Falha ao iniciar instância $USER_TOKEN${NC}"
    fi
done

echo "INSTANCES_RUNNING" > "$CONTROL_FILE"

echo -e "${GREEN}\n======================================================${NC}"
echo -e "${GREEN}         TODAS AS INSTÂNCIAS FORAM INICIADAS           ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${YELLOW}\nPARA CONECTAR SEUS NÚMEROS:${NC}"

for USER_TOKEN in "${!USERS[@]}"; do
    PORT="${USERS[$USER_TOKEN]}"
    echo -e "${CYAN}● TOKEN ${YELLOW}$USER_TOKEN${CYAN}: ${BLUE}http://localhost:$PORT/login?token=$USER_TOKEN${NC}"
done

echo -e "\n${GREEN}Agora você pode fazer o pareamento no Tasker!${NC}"
EOF

    chmod +x "$HOME/start_all_wuzapi.sh"
    
    # Script para parar todas as instâncias
    cat << 'EOF' > "$HOME/stop_all_wuzapi.sh"
#!/data/data/com.termux/files/usr/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Parando todas as instâncias WuzAPI...${NC}"

# Parar por PID files
for pidfile in "$HOME"/wuzapi_*.pid; do
    if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile")
        if ps -p $PID > /dev/null; then
            kill -9 $PID
            echo -e "${GREEN}✓ Processo $PID parado${NC}"
        fi
        rm "$pidfile"
    fi
done

# Parar por portas
for PORT in 8080 8081; do
    PORT_PROCESS=$(lsof -t -i:$PORT 2>/dev/null)
    if [ -n "$PORT_PROCESS" ]; then
        kill -9 $PORT_PROCESS
        echo -e "${GREEN}✓ Porta $PORT liberada${NC}"
    fi
done

echo "INSTANCES_STOPPED" > "/storage/emulated/0/Tasker/termux/TASKER-WUZAPI/wuzapi_control.txt"
echo -e "${GREEN}Todas as instâncias foram paradas!${NC}"
EOF

    chmod +x "$HOME/stop_all_wuzapi.sh"
    
    show_success "Scripts de controle criados"
    show_success "  - $HOME/start_all_wuzapi.sh (Para iniciar)"
    show_success "  - $HOME/stop_all_wuzapi.sh (Para parar)"
    return 0
}

# Mostrar instruções finais
show_final_instructions() {
    echo -e "${GREEN}\n\n======================================================${NC}"
    echo -e "${GREEN}          INSTALAÇÃO E CONFIGURAÇÃO CONCLUÍDA!        ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    
    echo -e "${YELLOW}\n🎯 PRÓXIMOS PASSOS:${NC}"
    echo -e "${CYAN}1. Configure seu Tasker conforme necessário${NC}"
    echo -e "${CYAN}2. Quando estiver pronto para iniciar as instâncias, execute:${NC}"
    echo -e "   ${BLUE}bash $HOME/start_all_wuzapi.sh${NC}"
    echo ""
    echo -e "${YELLOW}📋 COMANDOS DISPONÍVEIS:${NC}"
    echo -e "${GREEN}• Iniciar todas as instâncias:${NC}"
    echo -e "  ${BLUE}bash $HOME/start_all_wuzapi.sh${NC}"
    echo -e "${GREEN}• Parar todas as instâncias:${NC}"
    echo -e "  ${BLUE}bash $HOME/stop_all_wuzapi.sh${NC}"
    echo ""
    echo -e "${YELLOW}🔗 URLS DE PAREAMENTO (após iniciar):${NC}"
    for USER_TOKEN in "${!USERS[@]}"; do
        PORT="${USERS[$USER_TOKEN]}"
        echo -e "${CYAN}• Token ${YELLOW}$USER_TOKEN${CYAN}: ${BLUE}http://localhost:$PORT/login?token=$USER_TOKEN${NC}"
    done
    
    echo -e "\n${GREEN}======================================================${NC}"
    echo -e "${GREEN}   CONFIGURAÇÃO FINALIZADA - PRONTO PARA O TASKER!    ${NC}"
    echo -e "${GREEN}======================================================${NC}\n"
    
    save_status "SETUP_COMPLETE"
}

# Função para verificar status e continuar de onde parou
check_and_continue() {
    local current_status=$(read_status)
    
    case "$current_status" in
        "NOT_STARTED")
            echo -e "${CYAN}Iniciando instalação completa...${NC}"
            ;;
        "ENVIRONMENT_SETUP")
            echo -e "${YELLOW}Continuando da instalação de dependências...${NC}"
            ;;
        "DEPENDENCIES_INSTALLED")
            echo -e "${YELLOW}Continuando da configuração de instâncias...${NC}"
            ;;
        "INSTANCES_CONFIGURED")
            echo -e "${YELLOW}Continuando da criação de scripts...${NC}"
            ;;
        "SETUP_COMPLETE")
            echo -e "${GREEN}Instalação já completa!${NC}"
            show_final_instructions
            return 0
            ;;
        "INSTANCES_RUNNING")
            echo -e "${GREEN}Instâncias já estão rodando!${NC}"
            echo -e "${BLUE}Use: bash $HOME/stop_all_wuzapi.sh para parar${NC}"
            return 0
            ;;
    esac
    
    return 1
}

# Fluxo principal
main() {
    echo -e "${PURPLE}======================================================${NC}"
    echo -e "${PURPLE}     WUZAPI MULTI-TOKEN INSTALLER & CONFIGURATOR      ${NC}"
    echo -e "${PURPLE}======================================================${NC}\n"
    
    # Verificar se pode continuar de onde parou
    if check_and_continue; then
        return 0
    fi
    
    local current_status=$(read_status)
    
    # Executar etapas conforme o status
    case "$current_status" in
        "NOT_STARTED")
            if ! setup_environment; then
                show_error "Falha na configuração do ambiente"
                exit 1
            fi
            ;&  # Continua para a próxima etapa
        "ENVIRONMENT_SETUP")
            if ! install_dependencies; then
                show_error "Falha na instalação de dependências"
                exit 1
            fi
            ;&  # Continua para a próxima etapa
        "DEPENDENCIES_INSTALLED")
            if ! setup_instances; then
                show_error "Falha na configuração das instâncias"
                exit 1
            fi
            ;&  # Continua para a próxima etapa
        "INSTANCES_CONFIGURED")
            if ! create_control_scripts; then
                show_error "Falha na criação dos scripts de controle"
                exit 1
            fi
            show_final_instructions
            ;;
    esac
}

# Executar apenas se o script foi chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi