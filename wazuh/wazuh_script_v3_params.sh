#!/bin/bash

# =========================================
# Instalador Wazuh Agent com TLS - Versão 3.0 (ACEITA PARÂMETROS)
# Modelo de leitura de certificados IGUAL ao Zabbix
# Verificação de instalação existente + Remoção automática do client.keys
# ======================================

set -e

echo "=== Instalação do Wazuh Agent com TLS ==="

# =========================================
# FUNÇÕES AUXILIARES
# =========================================

# Função para verificar se o Wazuh Agent está instalado
check_wazuh_installation() {
    if dpkg -l | grep -q "wazuh-agent"; then
        return 0  # Instalado
    else
        return 1  # Não instalado
    fi
}

# Função para verificar se o serviço Wazuh Agent está rodando
check_wazuh_service() {
    if systemctl is-active --quiet wazuh-agent; then
        return 0  # Rodando
    else
        return 1  # Parado
    fi
}


# Função para exibir informações do agente existente
show_existing_agent_info() {
    echo "=== AGENTE WAZUH JÁ INSTALADO ==="
    
    if [ -f "/var/ossec/etc/ossec.conf" ]; then
        echo "Configuração atual encontrada em /var/ossec/etc/ossec.conf"
        
        # Extrair informações da configuração existente
        if grep -q "<address>" /var/ossec/etc/ossec.conf; then
            CURRENT_MANAGER=$(grep -A1 "<server>" /var/ossec/etc/ossec.conf | grep "<address>" | sed 's/.*<address>\(.*\)<\/address>.*/\1/' | tr -d ' ')
            echo "Manager atual: $CURRENT_MANAGER"
        fi
        
        if grep -q "<agent_name>" /var/ossec/etc/ossec.conf; then
            CURRENT_AGENT_NAME=$(grep "<agent_name>" /var/ossec/etc/ossec.conf | sed 's/.*<agent_name>\(.*\)<\/agent_name>.*/\1/' | tr -d ' ')
            echo "Nome do agente atual: $CURRENT_AGENT_NAME"
        fi
    fi
    
    if check_wazuh_service; then
        echo "Status do serviço: RODANDO"
    else
        echo "Status do serviço: PARADO"
    fi
    
    echo
}

# Função para desinstalar o Wazuh Agent completamente
uninstall_wazuh_agent() {
    echo "=== DESINSTALANDO WAZUH AGENT ==="
    
    # Parar o serviço se estiver rodando
    if check_wazuh_service; then
        echo "Parando serviço wazuh-agent..."
        systemctl stop wazuh-agent 2>/dev/null || true
    fi
    
    # Desabilitar o serviço
    echo "Desabilitando serviço wazuh-agent..."
    systemctl disable wazuh-agent 2>/dev/null || true
    
    # Fazer backup das configurações antes de remover (opcional)
    if [ -d "/var/ossec" ]; then
        BACKUP_DIR="/tmp/wazuh_backup_$(date +%Y%m%d_%H%M%S)"
        echo "Criando backup das configurações em $BACKUP_DIR..."
        mkdir -p "$BACKUP_DIR"
        cp -r /var/ossec/etc "$BACKUP_DIR/" 2>/dev/null || true
        echo "✓ Backup criado em $BACKUP_DIR"
    fi
    
    # Remover o pacote
    echo "Removendo pacote wazuh-agent..."
    if dpkg --purge wazuh-agent; then
        echo "✓ Pacote wazuh-agent removido com sucesso"
    else
        echo "AVISO: Falha ao remover pacote, tentando forçar..."
        dpkg --remove --force-remove-reinstreq wazuh-agent 2>/dev/null || true
    fi
    
    # Limpar diretórios residuais
    echo "Limpando diretórios residuais..."
    rm -rf /var/ossec 2>/dev/null || true
    
    # Limpar cache do apt
    apt-get autoremove -y 2>/dev/null || true
    
    echo "✓ Wazuh Agent desinstalado completamente"
    echo
    return 0
}

# Função para remover client.keys com backup
remove_client_keys_safely() {
    local OSSEC_DIR="/var/ossec/etc"
    local CLIENT_KEYS_FILE="$OSSEC_DIR/client.keys"
    
    echo "=== Removendo client.keys para nova configuração ==="
    
    if [ ! -f "$CLIENT_KEYS_FILE" ]; then
        echo "Arquivo client.keys não encontrado (já removido ou nunca existiu)"
        return 0
    fi
    
    echo "Arquivo client.keys encontrado em: $CLIENT_KEYS_FILE"
    
    # Exibir informações do arquivo atual
    echo "Tamanho: $(du -h "$CLIENT_KEYS_FILE" | cut -f1)"
    echo "Permissões: $(ls -l "$CLIENT_KEYS_FILE" | awk '{print $1, $3, $4}')"
    
    # Mostrar conteúdo se não estiver vazio
    if [ -s "$CLIENT_KEYS_FILE" ]; then
        echo "Conteúdo atual do client.keys:"
        echo "--------------------------------"
        cat "$CLIENT_KEYS_FILE" | head -5
        if [ $(wc -l < "$CLIENT_KEYS_FILE") -gt 5 ]; then
            echo "... ($(wc -l < "$CLIENT_KEYS_FILE") linhas total)"
        fi
        echo "--------------------------------"
    else
        echo "O arquivo client.keys está vazio."
    fi
    
    # Confirmar remoção
    echo
    echo "ATENÇÃO: Este arquivo contém as chaves de autenticação do agente atual."
    echo "Removê-lo é necessário para reconfigurar o agente com novos certificados TLS."
    echo
    read -p "Deseja prosseguir com a remoção do client.keys? (s/n): " CONFIRM
    
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Operação cancelada pelo usuário."
        return 1
    fi
    
    # Fazer backup antes da remoção
    local BACKUP_FILE="${CLIENT_KEYS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Criando backup do client.keys..."
    
    if cp "$CLIENT_KEYS_FILE" "$BACKUP_FILE"; then
        echo "✓ Backup criado: $BACKUP_FILE"
    else
        echo "ERRO: Falha ao criar backup"
        return 1
    fi
    
    # Remover o arquivo
    echo "Removendo client.keys..."
    if rm -f "$CLIENT_KEYS_FILE"; then
        echo "✓ client.keys removido com sucesso"
    else
        echo "ERRO: Falha ao remover client.keys"
        echo "Restaurando backup..."
        cp "$BACKUP_FILE" "$CLIENT_KEYS_FILE"
        return 1
    fi
    
    # Parar o serviço se estiver rodando
    if check_wazuh_service; then
        echo "Parando serviço wazuh-agent para reconfiguração..."
        if systemctl stop wazuh-agent; then
            echo "✓ Serviço parado com sucesso"
        else
            echo "AVISO: Falha ao parar o serviço wazuh-agent"
        fi
    fi
    
    return 0
}

# =========================================
# VERIFICAÇÃO DE ROOT
# =========================================
if [[ $EUID -ne 0 ]]; then
    echo "ERRO: execute com sudo"
    echo "Exemplo: sudo ./wazuh_quefunfa_v3_params.sh"
    exit 1
fi

# =========================================
# RECEBER PARÂMETROS
# =========================================
WAZUH_MANAGER="${1}"
WAZUH_AGENT_NAME="${2}"
WAZUH_AGENT_GROUP="${3:-default}"

if [[ -z "$WAZUH_MANAGER" ]]; then
    echo "ERRO: IP do Wazuh Manager é obrigatório"
    echo "Uso: sudo $0 <IP_MANAGER> <NOME_AGENTE> [GRUPO]"
    exit 1
fi

if [[ -z "$WAZUH_AGENT_NAME" ]]; then
    echo "ERRO: Nome do agente é obrigatório"
    echo "Uso: sudo $0 <IP_MANAGER> <NOME_AGENTE> [GRUPO]"
    exit 1
fi

echo "=== Configurações recebidas ==="
echo "Manager: $WAZUH_MANAGER"
echo "Agente: $WAZUH_AGENT_NAME"
echo "Grupo: $WAZUH_AGENT_GROUP"


# =========================================
# VERIFICAÇÃO DE INSTALAÇÃO EXISTENTE
# =========================================
if check_wazuh_installation; then
    echo "Detectado Wazuh Agent já instalado no sistema."
    show_existing_agent_info
    
    echo "Escolha uma opção:"
    echo "(1) Cancelar/Sair"
    echo "(2) Reconfigurar o agente existente"
    echo "(3) Desinstalar e instalar um novo agente"
    echo
    read -p "Opção (1-3): " OPTION
    
    case $OPTION in
        1)
            echo "Operação cancelada pelo usuário."
            exit 0
            ;;
        2)
            echo "Continuando com a reconfiguração do agente existente..."
            SKIP_INSTALLATION=true
            
            # =========================================
            # REMOVER CLIENT.KEYS PARA NOVA CONFIGURAÇÃO
            # =========================================
            if ! remove_client_keys_safely; then
                echo "ERRO: Falha na remoção do client.keys. Abortando reconfiguração."
                exit 1
            fi
            ;;
        3)
            echo "Continuando com a desinstalação e nova instalação..."
            
            # Desinstalar agente atual
            if ! uninstall_wazuh_agent; then
                echo "ERRO: Falha na desinstalação do agente atual. Abortando."
                exit 1
            fi
            
            # Definir para fazer nova instalação
            SKIP_INSTALLATION=false
            ;;
        *)
            echo "Opção inválida. Execute o script novamente."
            exit 1
            ;;
    esac
    
else
    echo "Wazuh Agent não encontrado. Prosseguindo com a instalação."
    SKIP_INSTALLATION=false
fi

# =========================================
# DETECTAR ARQUITETURA
# =========================================
ARCH=$(dpkg --print-architecture)

case "$ARCH" in
    amd64|arm64) ;;
    *)
        echo "Arquitetura não suportada: $ARCH"
        exit 1
        ;;
esac

# =========================================
# DOWNLOAD E INSTALAÇÃO (APENAS SE NECESSÁRIO)
# =========================================
if [ "$SKIP_INSTALLATION" = false ]; then
    PKG="wazuh-agent_4.14.0-1_${ARCH}.deb"
    URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${PKG}"

    echo "Baixando Wazuh Agent (${ARCH})..."
    if ! wget -q --show-progress "$URL"; then
        echo "ERRO: Falha no download do Wazuh Agent"
        exit 1
    fi

    echo "Instalando Wazuh Agent..."
    if ! WAZUH_MANAGER="$WAZUH_MANAGER" \
         WAZUH_AGENT_GROUP="$WAZUH_AGENT_GROUP" \
         WAZUH_AGENT_NAME="$WAZUH_AGENT_NAME" \
         dpkg -i "./$PKG"; then
        echo "ERRO: Falha na instalação do Wazuh Agent"
        exit 1
    fi
    
    echo "✓ Wazuh Agent instalado com sucesso"
else
    echo "Pulando instalação (agente já existe)"
fi

# =========================================
# CAMINHOS TLS
# =========================================
OSSEC_DIR="/var/ossec/etc"
CERT_FILE="$OSSEC_DIR/sslagent.cert"
KEY_FILE="$OSSEC_DIR/sslagent.key"

# Verificar se os diretórios existem
if [ ! -d "$OSSEC_DIR" ]; then
    echo "ERRO: Diretório $OSSEC_DIR não encontrado"
    exit 1
fi

# =========================================
# COLETA DO CERTIFICADO (MODELO ZABBIX)
# =========================================
echo
echo "=== Certificado do Agente ==="
echo "Cole o certificado COMPLETO"
echo "Finalize pressionando ENTER duas vezes"
echo "-----END CERTIFICATE-----"

CERT_CONTENT=""
while IFS= read -r line; do
    if [[ -z "$line" && -n "$CERT_CONTENT" ]]; then
        break
    fi
    CERT_CONTENT+="$line"$'\n'
done

if [ -z "$CERT_CONTENT" ]; then
    echo "ERRO: Nenhum conteúdo de certificado fornecido"
    exit 1
fi

echo "$CERT_CONTENT" > "$CERT_FILE"
echo "✓ Certificado salvo em $CERT_FILE"

# =========================================
# COLETA DA CHAVE PRIVADA (MODELO ZABBIX)
# =========================================
echo
echo "=== Chave Privada do Agente ==="
echo "Cole a chave COMPLETA"
echo "Finalize pressionando ENTER duas vezes"
echo "-----END PRIVATE KEY-----"

KEY_CONTENT=""
while IFS= read -r line; do
    if [[ -z "$line" && -n "$KEY_CONTENT" ]]; then
        break
    fi
    KEY_CONTENT+="$line"$'\n'
done

if [ -z "$KEY_CONTENT" ]; then
    echo "ERRO: Nenhum conteúdo de chave privada fornecido"
    exit 1
fi

echo "$KEY_CONTENT" > "$KEY_FILE"
echo "✓ Chave privada salva em $KEY_FILE"

# Permissões
chmod 640 "$KEY_FILE"
chmod 644 "$CERT_FILE"
chown root:wazuh "$KEY_FILE" "$CERT_FILE"
echo "✓ Permissões configuradas"

# =========================================
# CONFIGURAÇÃO DO OSSEC.CONF
# =========================================
OSSEC_CONF="$OSSEC_DIR/ossec.conf"

if [ ! -f "$OSSEC_CONF" ]; then
    echo "ERRO: Arquivo de configuração $OSSEC_CONF não encontrado"
    exit 1
fi

echo "Configurando ossec.conf..."

# Backup da configuração original
cp "$OSSEC_CONF" "${OSSEC_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
echo "✓ Backup da configuração criado"

# Remove configs antigas
sed -i '/authorization_pass_path/d' "$OSSEC_CONF"
sed -i '/<client>/,/<\/client>/d' "$OSSEC_CONF"

# Insere nova configuração
sed -i "/<\/ossec_config>/i \
<client>\n\
  <server>\n\
    <address>${WAZUH_MANAGER}</address>\n\
  </server>\n\
  <enrollment>\n\
    <enabled>yes</enabled>\n\
    <agent_name>${WAZUH_AGENT_NAME}</agent_name>\n\
    <agent_certificate_path>${CERT_FILE}</agent_certificate_path>\n\
    <agent_key_path>${KEY_FILE}</agent_key_path>\n\
  </enrollment>\n\
</client>\n" "$OSSEC_CONF"

echo "✓ Configuração do ossec.conf atualizada"

# =========================================
# REINICIAR AGENTE
# =========================================
echo "Iniciando/reiniciando wazuh-agent..."

if ! systemctl start wazuh-agent; then
    echo "ERRO: Falha ao iniciar o serviço wazuh-agent"
    exit 1
fi

# Aguardar o serviço inicializar
sleep 3

if check_wazuh_service; then
    echo "✓ Serviço wazuh-agent iniciado com sucesso"
else
    echo "AVISO: Serviço wazuh-agent não está rodando após início"
    echo "Verifique os logs: tail -f /var/ossec/logs/ossec.log"
fi

# =========================================
# FINALIZAÇÃO
# =========================================
echo
echo "=== CONFIGURAÇÃO CONCLUÍDA ==="
echo "Agent: $WAZUH_AGENT_NAME"
echo "Manager: $WAZUH_MANAGER"
echo "Grupo: $WAZUH_AGENT_GROUP"
echo "Certificado: $CERT_FILE"
echo "Chave privada: $KEY_FILE"
echo
echo "Status do serviço:"
systemctl status wazuh-agent --no-pager -l
echo
echo "Para acompanhar os logs:"
echo "tail -f /var/ossec/logs/ossec.log"
echo
echo "Para verificar a conexão com o manager:"
echo "/var/ossec/bin/agent-control -l"
echo
echo "Para verificar se o agente está conectado:"
echo "/var/ossec/bin/agent-control -l"
