#!/bin/bash

# ================================
# Instalador automático Zabbix Agent / Agent2 com TLS (ACEITA PARÂMETROS)
# ================================

set -e

echo "=== Instalação do Agente Zabbix ==="

# ================================
# RECEBER PARÂMETROS
# ================================
ZBX_SERVER_IP="${1}"
HOSTNAME_ZABBIX="${2}"
USE_TLS="${3:-1}"

if [[ -z "$ZBX_SERVER_IP" ]]; then
    echo "ERRO: IP do servidor Zabbix é obrigatório"
    echo "Uso: sudo $0 <IP_SERVIDOR> <HOSTNAME_AGENTE> [USE_TLS]"
    echo "USE_TLS: 1=TLS (padrão), 2=Sem TLS"
    exit 1
fi

if [[ -z "$HOSTNAME_ZABBIX" ]]; then
    echo "ERRO: Hostname do agente Zabbix é obrigatório"
    echo "Uso: sudo $0 <IP_SERVIDOR> <HOSTNAME_AGENTE> [USE_TLS]"
    echo "USE_TLS: 1=TLS (padrão), 2=Sem TLS"
    exit 1
fi

echo "=== Configurações recebidas ==="
echo "IP do servidor: $ZBX_SERVER_IP"
echo "Hostname do agente: $HOSTNAME_ZABBIX"
echo "Usar TLS: $([ "$USE_TLS" = "1" ] && echo "Sim" || echo "Não")"

# ================================
# VERIFICAÇÕES INICIAIS
# ================================
echo "Verificando se está executando com sudo..."

# Verificar se é root
if [[ $EUID -eq 0 ]]; then
    echo "✓ Executando como root"
elif sudo -n true 2>/dev/null; then
    echo "✓ Sudo disponível e funcionando"
else
    echo "ERRO: Este script precisa ser executado com privilégios de sudo"
    echo ""
    echo "Execute o script da seguinte forma:"
    echo "sudo ./install_zabbix_agent_fixed_params.sh"
    echo ""
    echo "Ou torne o script executável e execute:"
    echo "chmod +x install_zabbix_agent_fixed_params.sh"
    echo "sudo ./install_zabbix_agent_fixed_params.sh"
    exit 1
fi

# ================================
# CONFIGURAÇÕES TLS
# ================================
if [[ "$USE_TLS" == "1" ]]; then
    echo "Configurando TLS..."
    TLS_CA="/etc/zabbix/ssl/agente/ca.crt"
    TLS_CERT="/etc/zabbix/ssl/agente/agent.crt"
    TLS_KEY="/etc/zabbix/ssl/agente/agent.key"
    
    # Informações do certificado do servidor
    TLS_ISSUER="CN=CARootCA,OU=CA,O=CAZabbix,ST=SP,C=BR"
    TLS_SUBJECT_SERVER="CN=zabbix-server,OU=Server,O=CAZabbix,ST=SP,C=BR"
else
    echo "AVISO: Usando conexão sem TLS. Para produção, recomenda-se TLS."
fi

# ================================
# DETECTAR VERSÃO DO UBUNTU
# ================================
echo "Detectando versão do Ubuntu..."
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")

if [[ "$UBUNTU_VER" == "unknown" ]]; then
    echo "ERRO: Não foi possível detectar a versão do Ubuntu"
    exit 1
fi

echo "Ubuntu detectado: $UBUNTU_VER"

case "$UBUNTU_VER" in
    20.04)
        RELEASE_FILE="zabbix-release_latest_7.4+ubuntu20.04_all.deb"
        ;;
    22.04)
        RELEASE_FILE="zabbix-release_latest_7.4+ubuntu22.04_all.deb"
        ;;
    24.04)
        RELEASE_FILE="zabbix-release_latest_7.4+ubuntu24.04_all.deb"
        ;;
    *)
        echo "Versão do Ubuntu não suportada automaticamente: $UBUNTU_VER"
        echo "Versões suportadas: 20.04, 22.04, 24.04"
        echo "Para outras versões, baixe manualmente o pacote correto"
        exit 1
        ;;
esac

# ================================
# CRIAR PASTA PARA INSTALAÇÃO
# ================================
INSTALL_DIR="$HOME/zabbix_install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo "Baixando pacote de repositório do Zabbix..."
RELEASE_URL="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/$RELEASE_FILE"
if ! wget "$RELEASE_URL"; then
    echo "ERRO: Falha ao baixar o pacote de repositório"
    exit 1
fi

echo "Instalando pacote de repositório..."
if ! sudo dpkg -i "$RELEASE_FILE"; then
    echo "ERRO: Falha ao instalar o pacote de repositório"
    exit 1
fi

echo "Atualizando pacotes..."
if ! sudo apt update -y; then
    echo "ERRO: Falha ao atualizar pacotes"
    exit 1
fi

# ================================
# ESCOLHA AGENT OU AGENT2
# ================================
echo
echo "Deseja instalar o Zabbix Agent 1 ou Agent2?"
echo "1 - Agent (Legacy)"
echo "2 - Agent2 (Recomendado)"
read -p "Escolha (1/2): " AGENT_CHOICE

if [[ "$AGENT_CHOICE" == "1" ]]; then
    AGENT_PACKAGE="zabbix-agent"
    CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
    AGENT_BINARY="zabbix_agentd"
elif [[ "$AGENT_CHOICE" == "2" ]]; then
    AGENT_PACKAGE="zabbix-agent2"
    CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
    AGENT_BINARY="zabbix_agent2"
else
    echo "Opção inválida."
    exit 1
fi

echo "Instalando $AGENT_PACKAGE..."
if ! sudo apt install -y "$AGENT_PACKAGE"; then
    echo "ERRO: Falha ao instalar $AGENT_PACKAGE"
    exit 1
fi

echo "Agente instalado! Configurando..."

# ================================
# FAZER BACKUP DO ARQUIVO DE CONFIGURAÇÃO
# ================================
if [[ -f "$CONFIG_FILE" ]]; then
    sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backup do arquivo de configuração criado"
fi

# ================================
# CONFIGURAR ARQUIVO DE CONFIGURAÇÃO BÁSICO
# ================================
echo "Configurando parâmetros básicos..."

# Remover comentários e configurações existentes
sudo sed -i '/^Server=/d' "$CONFIG_FILE" 2>/dev/null || true
sudo sed -i '/^ServerActive=/d' "$CONFIG_FILE" 2>/dev/null || true
sudo sed -i '/^Hostname=/d' "$CONFIG_FILE" 2>/dev/null || true

# Adicionar novas configurações
echo "Server=$ZBX_SERVER_IP" | sudo tee -a "$CONFIG_FILE" >/dev/null
echo "ServerActive=$ZBX_SERVER_IP" | sudo tee -a "$CONFIG_FILE" >/dev/null
echo "Hostname=$HOSTNAME_ZABBIX" | sudo tee -a "$CONFIG_FILE" >/dev/null

# ================================
# CONFIGURAR TLS SE SOLICITADO
# ================================
if [[ "$USE_TLS" == "1" ]]; then
    echo "Configurando TLS..."
    
    # Criar diretórios SSL
    sudo mkdir -p /etc/zabbix/ssl/agente
    
    # Remover configurações TLS existentes
    sudo sed -i '/^TLSConnect=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSAccept=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSCAFile=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSCertFile=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSKeyFile=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSServerCertIssuer=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSServerCertSubject=/d' "$CONFIG_FILE" 2>/dev/null || true
    
    # Adicionar configurações TLS
    echo "" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "### TLS CONFIGURATION ###" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSConnect=cert" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSAccept=cert" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSCAFile=$TLS_CA" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSCertFile=$TLS_CERT" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSKeyFile=$TLS_KEY" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSServerCertIssuer=$TLS_ISSUER" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSServerCertSubject=$TLS_SUBJECT_SERVER" | sudo tee -a "$CONFIG_FILE" >/dev/null
    
    # Configurar permissões corretas
    sudo chown -R zabbix:zabbix /etc/zabbix/ssl
    
    # ================================
    # COLETAR CONTEÚDO DOS CERTIFICADOS
    # ================================
    
    # Certificado CA
    echo
    echo "1/3 - Certificado da CA (ca.crt):"
    echo "Cole o conteúdo do certificado da CA e pressione ENTER duas vezes para finalizar:"
    echo "-----END CERTIFICATE-----"
    CA_CONTENT=""
    while IFS= read -r line; do
        if [[ -z "$line" && -n "$CA_CONTENT" ]]; then
            break
        fi
        CA_CONTENT+="$line"$'\n'
    done
    
    # Certificado do Agente
    echo
    echo "2/3 - Certificado do Agente (agent.crt):"
    echo "Cole o conteúdo do certificado do agente e pressione ENTER duas vezes para finalizar:"
    echo "-----END CERTIFICATE-----"
    AGENT_CERT_CONTENT=""
    while IFS= read -r line; do
        if [[ -z "$line" && -n "$AGENT_CERT_CONTENT" ]]; then
            break
        fi
        AGENT_CERT_CONTENT+="$line"$'\n'
    done
    
    # Chave Privada do Agente
    echo
    echo "3/3 - Chave Privada do Agente (agent.key):"
    echo "Cole o conteúdo da chave privada e pressione ENTER duas vezes para finalizar:"
    echo "-----END PRIVATE KEY-----"
    AGENT_KEY_CONTENT=""
    while IFS= read -r line; do
        if [[ -z "$line" && -n "$AGENT_KEY_CONTENT" ]]; then
            break
        fi
        AGENT_KEY_CONTENT+="$line"$'\n'
    done
    
    # Criar arquivos de certificado
    echo
    echo "Criando arquivos de certificado..."
    
    echo "$CA_CONTENT" | sudo tee "$TLS_CA" >/dev/null
    echo "$AGENT_CERT_CONTENT" | sudo tee "$TLS_CERT" >/dev/null
    echo "$AGENT_KEY_CONTENT" | sudo tee "$TLS_KEY" >/dev/null
    
    # Configurar permissões finais
    sudo chmod 644 "$TLS_CA" "$TLS_CERT"
    sudo chmod 600 "$TLS_KEY"
    sudo chown zabbix:zabbix "$TLS_CA" "$TLS_CERT" "$TLS_KEY"
    echo "✓ Certificados criados e configurados com sucesso!"
else
    # Para conexões sem TLS, configurar como unencrypted
    sudo sed -i '/^TLSConnect=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sed -i '/^TLSAccept=/d' "$CONFIG_FILE" 2>/dev/null || true
    echo "" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "### CONNECTION SECURITY ###" | sudo tee -a "$CONFIG_FILE" >/dev/null
    echo "TLSAccept=unencrypted" | sudo tee -a "$CONFIG_FILE" >/dev/null
fi

# ================================
# INICIAR E HABILITAR SERVIÇO
# ================================
echo "Habilitando e iniciando serviço do agente..."

# Parar qualquer instância existente
sudo systemctl stop "$AGENT_SERVICE" 2>/dev/null || true

if ! sudo systemctl enable "$AGENT_SERVICE"; then
    echo "ERRO: Falha ao habilitar serviço $AGENT_SERVICE"
    exit 1
fi

if ! sudo systemctl start "$AGENT_SERVICE"; then
    echo "ERRO: Falha ao iniciar serviço $AGENT_SERVICE"
    echo "Verifique os logs com: sudo journalctl -u $AGENT_SERVICE -f"
    exit 1
fi

# Verificar status do serviço
if sudo systemctl is-active --quiet "$AGENT_SERVICE"; then
    echo "✓ Serviço $AGENT_SERVICE está rodando"
else
    echo "ERRO: Serviço $AGENT_SERVICE não está rodando"
    sudo systemctl status "$AGENT_SERVICE"
    exit 1
fi

# ================================
# LIMPEZA
# ================================
echo "Limpando arquivos temporários..."
cd "$HOME"
rm -rf "$INSTALL_DIR"

# ================================
# FINALIZAÇÃO
# ================================
echo
echo "=== Instalação concluída com sucesso! ==="
echo
echo "=== Informações de Verificação ==="
echo "Versão do agente:"
sudo "$AGENT_BINARY" -V 2>/dev/null || echo "Não foi possível obter a versão"

echo
echo "Status do serviço:"
sudo systemctl status "$AGENT_SERVICE" --no-pager -l

echo
echo "Logs recentes:"
sudo tail -n 10 "/var/log/zabbix/${AGENT_SERVICE}.log" 2>/dev/null || echo "Arquivo de log não encontrado"

echo
echo "=== Próximos Passos ==="
if [[ "$USE_TLS" == "1" ]]; then
    echo "1. Reinicie o agente: sudo systemctl restart $AGENT_SERVICE"
    echo "2. Teste a conexão: sudo $AGENT_BINARY -t system.uptime"
fi
echo "1. Configure o host na interface web do Zabbix:"
echo "   - Nome do host: $HOSTNAME_ZABBIX"
echo "   - IP do agente: $(hostname -I | awk '{print $1}')"
echo "   - Grupo de hosts apropriado"
echo "   - Templates recomendados: 'Linux by Zabbix agent' ou 'Linux by Zabbix agent active'"
echo
echo "Issuer:  CN=CARootCA,OU=CA,O=CAZabbix,ST=SP,C=BR"
echo "Subject: CN=$HOSTNAME_ZABBIX,OU=Agent,O=CAZabbix,ST=SP,C=BR"
echo
echo "Para monitorar logs: sudo tail -f /var/log/zabbix/${AGENT_SERVICE}.log"
echo "Para reiniciar: sudo systemctl restart $AGENT_SERVICE"
