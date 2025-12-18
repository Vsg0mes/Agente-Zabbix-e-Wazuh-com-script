#!/bin/bash

# =========================================
# Script Principal - Instalação Wazuh + Zabbix
# Executa ambos os agentes solicitando variáveis comuns apenas uma vez
# =========================================

set -e

echo "========================================="
echo "INSTALADOR AUTOMÁTICO - WAZUH + ZABBIX"
echo "========================================="
echo
echo "Este script irá instalar e configurar:"
echo "1. Wazuh Agent (com TLS)"
echo "2. Zabbix Agent (com TLS)"
echo
echo "As variáveis comuns serão solicitadas apenas uma vez."
echo

# =========================================
# FUNÇÕES AUXILIARES
# =========================================

# Função para verificar se o script existe
check_script_exists() {
    local script_path="$1"
    if [[ ! -f "$script_path" ]]; then
        echo "ERRO: Script não encontrado: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        echo "Aviso: Script não é executável, tornando executável..."
        chmod +x "$script_path"
    fi
    
    return 0
}

# Função para fazer o script executável
make_executable() {
    local script_path="$1"
    if [[ ! -x "$script_path" ]]; then
        chmod +x "$script_path"
        echo "✓ Script tornado executável: $script_path"
    fi
}

# =========================================
# VERIFICAR PRÉ-REQUISITOS
# =========================================
echo "=== Verificando Pré-requisitos ==="

# Verificar se está executando com sudo
if [[ $EUID -ne 0 ]]; then
    echo "ERRO: Execute este script com sudo"
    echo "Exemplo: sudo ./install_wazuh_zabbix_master.sh"
    exit 1
fi

echo "✓ Executando com privilégios de sudo"

# Definir caminhos dos scripts
WAZUH_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wazuh/wazuh_quefunfa_v3_params.sh"
ZABBIX_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/zabbix/install_zabbix_agent_fixed_params.sh"

# Verificar se os scripts existem
if ! check_script_exists "$WAZUH_SCRIPT"; then
    echo "Verifique se o script Wazuh existe em: $WAZUH_SCRIPT"
    exit 1
fi

if ! check_script_exists "$ZABBIX_SCRIPT"; then
    echo "Verifique se o script Zabbix existe em: $ZABBIX_SCRIPT"
    exit 1
fi

echo "✓ Scripts encontrados:"
echo "  - Wazuh: $WAZUH_SCRIPT"
echo "  - Zabbix: $ZABBIX_SCRIPT"

# Tornar scripts executáveis
make_executable "$WAZUH_SCRIPT"
make_executable "$ZABBIX_SCRIPT"


# =========================================
# COLETAR CONFIGURAÇÕES COMUNS
# =========================================
echo
echo "=== Configurações Comuns ==="
echo "As informações abaixo serão usadas para ambos os agentes:"

echo
read -p "IP do servidor (Wazuh e Zabbix): " SERVER_IP
[[ -z "$SERVER_IP" ]] && echo "IP do servidor é obrigatório" && exit 1

read -p "Nome do HOST (hostname para ambos os agentes): " HOSTNAME
[[ -z "$HOSTNAME" ]] && echo "Nome do host é obrigatório" && exit 1

read -p "Grupo Wazuh [default]: " WAZUH_GROUP
WAZUH_GROUP=${WAZUH_GROUP:-default}

echo
echo "=== Resumo das Configurações ==="
echo "Hostname: $HOSTNAME"
echo "IP do Servidor: $SERVER_IP"
echo "Grupo Wazuh: $WAZUH_GROUP"
echo "(O mesmo IP será usado para Wazuh Manager e Zabbix Server)"
echo

read -p "Confirma essas configurações? (s/n): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "Operação cancelada pelo usuário."
    exit 0
fi

# =========================================
# ESCOLHER ORDEM DE INSTALAÇÃO
# =========================================
echo
echo "=== Ordem de Instalação ==="
echo "Qual agente deseja instalar primeiro?"
echo "1 - Wazuh primeiro, depois Zabbix"
echo "2 - Zabbix primeiro, depois Wazix"
read -p "Escolha (1/2): " INSTALL_ORDER

case "$INSTALL_ORDER" in
    1)
        echo "Instalando na ordem: Wazuh → Zabbix"
        ;;
    2)
        echo "Instalando na ordem: Zabbix → Wazuh"
        ;;
    *)
        echo "Opção inválida. Usando ordem padrão: Wazuh → Zabbix"
        INSTALL_ORDER=1
        ;;
esac

# =========================================
# INSTALAÇÃO WAZUH
# =========================================
install_wazuh() {
    echo
    echo "========================================="
    echo "INSTALANDO WAZUH AGENT"
    echo "========================================="
    

    echo "Executando: $WAZUH_SCRIPT $SERVER_IP $HOSTNAME $WAZUH_GROUP"
    
    if ! "$WAZUH_SCRIPT" "$SERVER_IP" "$HOSTNAME" "$WAZUH_GROUP"; then
        echo "ERRO: Falha na instalação do Wazuh Agent"
        return 1
    fi
    
    echo "✓ Wazuh Agent instalado com sucesso"
    return 0
}

# =========================================
# INSTALAÇÃO ZABBIX
# =========================================
install_zabbix() {
    echo
    echo "========================================="
    echo "INSTALANDO ZABBIX AGENT"
    echo "========================================="
    

    echo "Executando: $ZABBIX_SCRIPT $SERVER_IP $HOSTNAME 1"
    
    if ! "$ZABBIX_SCRIPT" "$SERVER_IP" "$HOSTNAME" 1; then
        echo "ERRO: Falha na instalação do Zabbix Agent"
        return 1
    fi
    
    echo "✓ Zabbix Agent instalado com sucesso"
    return 0
}

# =========================================
# EXECUTAR INSTALAÇÕES
# =========================================
echo
echo "Iniciando processo de instalação..."

WAZUH_SUCCESS=false
ZABBIX_SUCCESS=false

if [[ "$INSTALL_ORDER" == "1" ]]; then
    # Wazuh primeiro
    if install_wazuh; then
        WAZUH_SUCCESS=true
        
        echo
        echo " Aguarde 3 segundos antes de continuar..."
        sleep 3
        
        if install_zabbix; then
            ZABBIX_SUCCESS=true
        fi
    fi
else
    # Zabbix primeiro
    if install_zabbix; then
        ZABBIX_SUCCESS=true
        
        echo
        echo " Aguarde 3 segundos antes de continuar..."
        sleep 3
        
        if install_wazuh; then
            WAZUH_SUCCESS=true
        fi
    fi
fi

# =========================================
# RELATÓRIO FINAL
# =========================================
echo
echo "========================================="
echo "RELATÓRIO DE INSTALAÇÃO"
echo "========================================="


if $WAZUH_SUCCESS; then
    echo "✓ Wazuh Agent: INSTALADO"
    echo "  - Manager: $SERVER_IP"
    echo "  - Agente: $HOSTNAME"
    echo "  - Grupo: $WAZUH_GROUP"
else
    echo "✗ Wazuh Agent: FALHOU"
fi

if $ZABBIX_SUCCESS; then
    echo "✓ Zabbix Agent: INSTALADO"
    echo "  - Server: $SERVER_IP"
    echo "  - Agente: $HOSTNAME"
    echo "  - TLS: Ativado"
else
    echo "✗ Zabbix Agent: FALHOU"
fi

echo
if $WAZUH_SUCCESS && $ZABBIX_SUCCESS; then
    echo "🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
    echo
    echo "=== Próximos Passos ==="
    echo "1. Configure os hosts nos respectivos servidores:"
    echo "   - Wazuh: Use o hostname $HOSTNAME"
    echo "   - Zabbix: Use o hostname $HOSTNAME"
    echo
    echo "2. Verifique os logs se necessário:"
    echo "   - Wazuh: tail -f /var/ossec/logs/ossec.log"
    echo "   - Zabbix: tail -f /var/log/zabbix/zabbix_agent2.log"
    echo
    echo "3. Status dos serviços:"
    echo "   - Wazuh: systemctl status wazuh-agent"
    echo "   - Zabbix: systemctl status zabbix-agent2"
    
elif $WAZUH_SUCCESS || $ZABBIX_SUCCESS; then
    echo "⚠️  INSTALAÇÃO PARCIAL"
    echo "Alguns agentes falharam. Verifique os erros acima."
else
    echo "❌ INSTALAÇÃO FALHOU"
    echo "Nenhum agente foi instalado com sucesso."
fi

echo
echo "========================================="
