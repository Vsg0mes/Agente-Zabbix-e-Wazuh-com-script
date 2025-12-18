#!/bin/bash

# =========================================
# Script de Gerenciamento - Wazuh + Zabbix
# Para reconfigurar agentes já instalados
# =========================================

set -e

echo "========================================="
echo "GERENCIADOR DE CONFIGURAÇÃO - WAZUH + ZABBIX"
echo "========================================="
echo
echo "Este script permite reconfigurar agentes já instalados:"
echo "1. Alterar IP do servidor"
echo "2. Alterar nome do agente/hostname"
echo "3. Regenerar/alterar certificados TLS"
echo "4. Verificar status dos agentes"
echo

# =========================================
# FUNÇÕES AUXILIARES
# =========================================

# Função para verificar se o Wazuh Agent está instalado
check_wazuh_installed() {
    if dpkg -l | grep -q "wazuh-agent"; then
        return 0  # Instalado
    else
        return 1  # Não instalado
    fi
}

# Função para verificar se o Zabbix Agent está instalado
check_zabbix_installed() {
    if dpkg -l | grep -q "zabbix-agent" || dpkg -l | grep -q "zabbix-agent2"; then
        return 0  # Instalado
    else
        return 1  # Não instalado
    fi
}

# Função para obter informações atuais do Wazuh
get_wazuh_current_config() {
    local config_file="/var/ossec/etc/ossec.conf"
    
    if [[ -f "$config_file" ]]; then
        # Extrair IP do manager atual
        CURRENT_WAZUH_MANAGER=$(grep -A1 "<server>" "$config_file" | grep "<address>" | sed 's/.*<address>\(.*\)<\/address>.*/\1/' | tr -d ' ' || echo "Não encontrado")
        
        # Extrair nome do agente atual
        CURRENT_WAZUH_AGENT=$(grep "<agent_name>" "$config_file" | sed 's/.*<agent_name>\(.*\)<\/agent_name>.*/\1/' | tr -d ' ' || echo "Não encontrado")
        
        # Verificar se TLS está configurado
        if grep -q "agent_certificate_path" "$config_file"; then
            WAZUH_TLS_STATUS="✓ Configurado"
        else
            WAZUH_TLS_STATUS="✗ Não configurado"
        fi
        
        # Status do serviço
        if systemctl is-active --quiet wazuh-agent; then
            WAZUH_SERVICE_STATUS="Rodando"
        else
            WAZUH_SERVICE_STATUS="Parado"
        fi
    else
        CURRENT_WAZUH_MANAGER="Arquivo não encontrado"
        CURRENT_WAZUH_AGENT="Arquivo não encontrado"
        WAZUH_TLS_STATUS="N/A"
        WAZUH_SERVICE_STATUS="N/A"
    fi
}

# Função para obter informações atuais do Zabbix
get_zabbix_current_config() {
    local config_file=""
    
    # Determinar qual agente está instalado
    if dpkg -l | grep -q "zabbix-agent2"; then
        config_file="/etc/zabbix/zabbix_agent2.conf"
        AGENT_TYPE="Agent2"
    elif dpkg -l | grep -q "zabbix-agent"; then
        config_file="/etc/zabbix/zabbix_agentd.conf"
        AGENT_TYPE="Agent"
    else
        CURRENT_ZABBIX_SERVER="Não instalado"
        CURRENT_ZABBIX_HOSTNAME="Não instalado"
        ZABBIX_TLS_STATUS="N/A"
        ZABBIX_SERVICE_STATUS="N/A"
        return
    fi
    
    if [[ -f "$config_file" ]]; then
        # Extrair IP do servidor atual
        CURRENT_ZABBIX_SERVER=$(grep "^Server=" "$config_file" | cut -d'=' -f2 | tr -d ' ' || echo "Não encontrado")
        
        # Extrair hostname atual
        CURRENT_ZABBIX_HOSTNAME=$(grep "^Hostname=" "$config_file" | cut -d'=' -f2 | tr -d ' ' || echo "Não encontrado")
        
        # Verificar se TLS está configurado
        if grep -q "^TLSConnect=cert" "$config_file"; then
            ZABBIX_TLS_STATUS="✓ Configurado"
        else
            ZABBIX_TLS_STATUS="✗ Não configurado"
        fi
        
        # Status do serviço
        if systemctl is-active --quiet zabbix-agent2; then
            ZABBIX_SERVICE_STATUS="Rodando"
        elif systemctl is-active --quiet zabbix-agent; then
            ZABBIX_SERVICE_STATUS="Rodando"
        else
            ZABBIX_SERVICE_STATUS="Parado"
        fi
    else
        CURRENT_ZABBIX_SERVER="Arquivo não encontrado"
        CURRENT_ZABBIX_HOSTNAME="Arquivo não encontrado"
        ZABBIX_TLS_STATUS="N/A"
        ZABBIX_SERVICE_STATUS="N/A"
    fi
}

# Função para alterar configuração do Wazuh
change_wazuh_config() {
    echo
    echo "=== RECONFIGURAR WAZUH AGENT ==="
    
    if ! check_wazuh_installed; then
        echo "❌ Wazuh Agent não está instalado"
        return 1
    fi
    
    get_wazuh_current_config
    
    echo "Configuração atual:"
    echo "  Manager: $CURRENT_WAZUH_MANAGER"
    echo "  Agente: $CURRENT_WAZUH_AGENT"
    echo "  TLS: $WAZUH_TLS_STATUS"
    echo "  Serviço: $WAZUH_SERVICE_STATUS"
    echo
    
    echo "O que deseja alterar?"
    echo "1. Alterar IP do servidor (Manager)"
    echo "2. Alterar nome do agente"
    echo "3. Regenerar certificados TLS"
    echo "4. Voltar ao menu principal"
    read -p "Escolha (1-4): " WAŻUH_CHOICE
    
    case $WAŻUH_CHOICE in
        1)
            echo
            read -p "Novo IP do servidor Wazuh: " NEW_WAZUH_MANAGER
            if [[ -z "$NEW_WAZUH_MANAGER" ]]; then
                echo "❌ IP obrigatório"
                return 1
            fi
            
            # Atualizar configuração
            local config_file="/var/ossec/etc/ossec.conf"
            if [[ -f "$config_file" ]]; then
                sed -i "s|<address>.*</address>|<address>${NEW_WAZUH_MANAGER}</address>|" "$config_file"
                echo "✓ IP do servidor atualizado para: $NEW_WAZUH_MANAGER"
                
                # Reiniciar serviço
                systemctl restart wazuh-agent
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Arquivo de configuração não encontrado"
                return 1
            fi
            ;;
        2)
            echo
            read -p "Novo nome do agente: " NEW_WAZUH_AGENT
            if [[ -z "$NEW_WAZUH_AGENT" ]]; then
                echo "❌ Nome do agente obrigatório"
                return 1
            fi
            
            # Atualizar configuração
            local config_file="/var/ossec/etc/ossec.conf"
            if [[ -f "$config_file" ]]; then
                sed -i "s|<agent_name>.*</agent_name>|<agent_name>${NEW_WAZUH_AGENT}</agent_name>|" "$config_file"
                echo "✓ Nome do agente atualizado para: $NEW_WAZUH_AGENT"
                
                # Remover client.keys para nova chave
                if [[ -f "/var/ossec/etc/client.keys" ]]; then
                    rm -f "/var/ossec/etc/client.keys"
                    echo "✓ client.keys removido (nova chave será gerada)"
                fi
                
                # Reiniciar serviço
                systemctl restart wazuh-agent
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Arquivo de configuração não encontrado"
                return 1
            fi
            ;;
        3)
            echo
            echo "Regenerando certificados TLS para Wazuh..."
            
            local cert_file="/var/ossec/etc/sslagent.cert"
            local key_file="/var/ossec/etc/sslagent.key"
            
            # Coletar novo certificado
            echo "Cole o novo certificado do agente:"
            echo "Finalize com ENTER duas vezes"
            echo "-----END CERTIFICATE-----"
            
            CERT_CONTENT=""
            while IFS= read -r line; do
                if [[ -z "$line" && -n "$CERT_CONTENT" ]]; then
                    break
                fi
                CERT_CONTENT+="$line"$'\n'
            done
            
            if [[ -n "$CERT_CONTENT" ]]; then
                echo "$CERT_CONTENT" > "$cert_file"
                chmod 644 "$cert_file"
                echo "✓ Certificado atualizado"
            else
                echo "❌ Nenhum conteúdo de certificado fornecido"
                return 1
            fi
            
            # Coletar nova chave privada
            echo
            echo "Cole a nova chave privada do agente:"
            echo "Finalize com ENTER duas vezes"
            echo "-----END PRIVATE KEY-----"
            
            KEY_CONTENT=""
            while IFS= read -r line; do
                if [[ -z "$line" && -n "$KEY_CONTENT" ]]; then
                    break
                fi
                KEY_CONTENT+="$line"$'\n'
            done
            
            if [[ -n "$KEY_CONTENT" ]]; then
                echo "$KEY_CONTENT" > "$key_file"
                chmod 640 "$key_file"
                chown root:wazuh "$key_file" "$cert_file"
                echo "✓ Chave privada atualizada"
                
                # Reiniciar serviço
                systemctl restart wazuh-agent
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Nenhum conteúdo de chave privada fornecido"
                return 1
            fi
            ;;
        4)
            return 0
            ;;
        *)
            echo "❌ Opção inválida"
            return 1
            ;;
    esac
}

# Função para alterar configuração do Zabbix
change_zabbix_config() {
    echo
    echo "=== RECONFIGURAR ZABBIX AGENT ==="
    
    if ! check_zabbix_installed; then
        echo "❌ Zabbix Agent não está instalado"
        return 1
    fi
    
    get_zabbix_current_config
    
    echo "Configuração atual:"
    echo "  Servidor: $CURRENT_ZABBIX_SERVER"
    echo "  Hostname: $CURRENT_ZABBIX_HOSTNAME"
    echo "  TLS: $ZABBIX_TLS_STATUS"
    echo "  Serviço: $ZABBIX_SERVICE_STATUS"
    echo "  Tipo: ${AGENT_TYPE:-Não detectado}"
    echo
    
    echo "O que deseja alterar?"
    echo "1. Alterar IP do servidor"
    echo "2. Alterar hostname do agente"
    echo "3. Regenerar certificados TLS"
    echo "4. Voltar ao menu principal"
    read -p "Escolha (1-4): " ZABBIX_CHOICE
    
    case $ZABBIX_CHOICE in
        1)
            echo
            read -p "Novo IP do servidor Zabbix: " NEW_ZABBIX_SERVER
            if [[ -z "$NEW_ZABBIX_SERVER" ]]; then
                echo "❌ IP obrigatório"
                return 1
            fi
            
            # Determinar arquivo de configuração
            local config_file=""
            local service_name=""
            
            if dpkg -l | grep -q "zabbix-agent2"; then
                config_file="/etc/zabbix/zabbix_agent2.conf"
                service_name="zabbix-agent2"
            elif dpkg -l | grep -q "zabbix-agent"; then
                config_file="/etc/zabbix/zabbix_agentd.conf"
                service_name="zabbix-agent"
            fi
            
            if [[ -f "$config_file" ]]; then
                sed -i "s|^Server=.*|Server=${NEW_ZABBIX_SERVER}|" "$config_file"
                sed -i "s|^ServerActive=.*|ServerActive=${NEW_ZABBIX_SERVER}|" "$config_file"
                echo "✓ IP do servidor atualizado para: $NEW_ZABBIX_SERVER"
                
                # Reiniciar serviço
                systemctl restart "$service_name"
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Arquivo de configuração não encontrado"
                return 1
            fi
            ;;
        2)
            echo
            read -p "Novo hostname do agente: " NEW_ZABBIX_HOSTNAME
            if [[ -z "$NEW_ZABBIX_HOSTNAME" ]]; then
                echo "❌ Hostname obrigatório"
                return 1
            fi
            
            # Determinar arquivo de configuração
            local config_file=""
            local service_name=""
            
            if dpkg -l | grep -q "zabbix-agent2"; then
                config_file="/etc/zabbix/zabbix_agent2.conf"
                service_name="zabbix-agent2"
            elif dpkg -l | grep -q "zabbix-agent"; then
                config_file="/etc/zabbix/zabbix_agentd.conf"
                service_name="zabbix-agent"
            fi
            
            if [[ -f "$config_file" ]]; then
                sed -i "s|^Hostname=.*|Hostname=${NEW_ZABBIX_HOSTNAME}|" "$config_file"
                echo "✓ Hostname atualizado para: $NEW_ZABBIX_HOSTNAME"
                
                # Reiniciar serviço
                systemctl restart "$service_name"
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Arquivo de configuração não encontrado"
                return 1
            fi
            ;;
        3)
            echo
            echo "Regenerando certificados TLS para Zabbix..."
            
            # Verificar se TLS está configurado
            local config_file=""
            if dpkg -l | grep -q "zabbix-agent2"; then
                config_file="/etc/zabbix/zabbix_agent2.conf"
            elif dpkg -l | grep -q "zabbix-agent"; then
                config_file="/etc/zabbix/zabbix_agentd.conf"
            fi
            
            if ! grep -q "^TLSConnect=cert" "$config_file"; then
                echo "❌ TLS não está configurado neste agente"
                return 1
            fi
            
            # Obter caminhos dos certificados
            local ca_file=$(grep "^TLSCAFile=" "$config_file" | cut -d'=' -f2)
            local cert_file=$(grep "^TLSCertFile=" "$config_file" | cut -d'=' -f2)
            local key_file=$(grep "^TLSKeyFile=" "$config_file" | cut -d'=' -f2)
            
            # Coletar novo certificado CA
            echo "Cole o novo certificado da CA:"
            echo "Finalize com ENTER duas vezes"
            echo "-----END CERTIFICATE-----"
            
            CA_CONTENT=""
            while IFS= read -r line; do
                if [[ -z "$line" && -n "$CA_CONTENT" ]]; then
                    break
                fi
                CA_CONTENT+="$line"$'\n'
            done
            
            if [[ -n "$CA_CONTENT" ]]; then
                echo "$CA_CONTENT" > "$ca_file"
                echo "✓ Certificado CA atualizado"
            else
                echo "❌ Nenhum conteúdo de certificado CA fornecido"
                return 1
            fi
            
            # Coletar novo certificado do agente
            echo
            echo "Cole o novo certificado do agente:"
            echo "Finalize com ENTER duas vezes"
            echo "-----END CERTIFICATE-----"
            
            AGENT_CERT_CONTENT=""
            while IFS= read -r line; do
                if [[ -z "$line" && -n "$AGENT_CERT_CONTENT" ]]; then
                    break
                fi
                AGENT_CERT_CONTENT+="$line"$'\n'
            done
            
            if [[ -n "$AGENT_CERT_CONTENT" ]]; then
                echo "$AGENT_CERT_CONTENT" > "$cert_file"
                echo "✓ Certificado do agente atualizado"
            else
                echo "❌ Nenhum conteúdo de certificado do agente fornecido"
                return 1
            fi
            
            # Coletar nova chave privada
            echo
            echo "Cole a nova chave privada do agente:"
            echo "Finalize com ENTER duas vezes"
            echo "-----END PRIVATE KEY-----"
            
            AGENT_KEY_CONTENT=""
            while IFS= read -r line; do
                if [[ -z "$line" && -n "$AGENT_KEY_CONTENT" ]]; then
                    break
                fi
                AGENT_KEY_CONTENT+="$line"$'\n'
            done
            
            if [[ -n "$AGENT_KEY_CONTENT" ]]; then
                echo "$AGENT_KEY_CONTENT" > "$key_file"
                chmod 600 "$key_file"
                chown zabbix:zabbix "$ca_file" "$cert_file" "$key_file"
                echo "✓ Chave privada atualizada"
                
                # Reiniciar serviço
                local service_name=""
                if dpkg -l | grep -q "zabbix-agent2"; then
                    service_name="zabbix-agent2"
                elif dpkg -l | grep -q "zabbix-agent"; then
                    service_name="zabbix-agent"
                fi
                
                systemctl restart "$service_name"
                echo "✓ Serviço reiniciado"
            else
                echo "❌ Nenhum conteúdo de chave privada fornecido"
                return 1
            fi
            ;;
        4)
            return 0
            ;;
        *)
            echo "❌ Opção inválida"
            return 1
            ;;
    esac
}

# Função para mostrar status dos agentes
show_agents_status() {
    echo
    echo "=== STATUS DOS AGENTES ==="
    
    # Status do Wazuh
    echo
    echo "--- WAZUH AGENT ---"
    if check_wazuh_installed; then
        get_wazuh_current_config
        echo "Status: ✓ Instalado"
        echo "Serviço: $WAZUH_SERVICE_STATUS"
        echo "Manager: $CURRENT_WAZUH_MANAGER"
        echo "Agente: $CURRENT_WAZUH_AGENT"
        echo "TLS: $WAZUH_TLS_STATUS"
        
        if systemctl is-active --quiet wazuh-agent; then
            echo "Últimos logs:"
            tail -n 3 /var/ossec/logs/ossec.log 2>/dev/null || echo "Log não disponível"
        fi
    else
        echo "Status: ✗ Não instalado"
    fi
    
    # Status do Zabbix
    echo
    echo "--- ZABBIX AGENT ---"
    if check_zabbix_installed; then
        get_zabbix_current_config
        echo "Status: ✓ Instalado"
        echo "Serviço: $ZABBIX_SERVICE_STATUS"
        echo "Servidor: $CURRENT_ZABBIX_SERVER"
        echo "Hostname: $CURRENT_ZABBIX_HOSTNAME"
        echo "TLS: $ZABBIX_TLS_STATUS"
        echo "Tipo: ${AGENT_TYPE:-Não detectado}"
        
        local service_name=""
        if dpkg -l | grep -q "zabbix-agent2"; then
            service_name="zabbix-agent2"
        elif dpkg -l | grep -q "zabbix-agent"; then
            service_name="zabbix-agent"
        fi
        
        if systemctl is-active --quiet "$service_name"; then
            echo "Últimos logs:"
            tail -n 3 "/var/log/zabbix/${service_name}.log" 2>/dev/null || echo "Log não disponível"
        fi
    else
        echo "Status: ✗ Não instalado"
    fi
}

# Função para reiniciar serviços
restart_services() {
    echo
    echo "=== REINICIAR SERVIÇOS ==="
    
    if check_wazuh_installed; then
        echo "Reiniciando Wazuh Agent..."
        if systemctl restart wazuh-agent; then
            echo "✓ Wazuh Agent reiniciado com sucesso"
        else
            echo "❌ Falha ao reiniciar Wazuh Agent"
        fi
    fi
    
    if check_zabbix_installed; then
        local service_name=""
        if dpkg -l | grep -q "zabbix-agent2"; then
            service_name="zabbix-agent2"
        elif dpkg -l | grep -q "zabbix-agent"; then
            service_name="zabbix-agent"
        fi
        
        echo "Reiniciando Zabbix Agent..."
        if systemctl restart "$service_name"; then
            echo "✓ Zabbix Agent reiniciado com sucesso"
        else
            echo "❌ Falha ao reiniciar Zabbix Agent"
        fi
    fi
}

# =========================================
# VERIFICAR PRÉ-REQUISITOS
# =========================================
echo "=== Verificando Pré-requisitos ==="

# Verificar se está executando com sudo
if [[ $EUID -ne 0 ]]; then
    echo "ERRO: Execute este script com sudo"
    echo "Exemplo: sudo ./manage_agents_config.sh"
    exit 1
fi

echo "✓ Executando com privilégios de sudo"

# =========================================
# MENU PRINCIPAL
# =========================================
show_menu() {
    echo
    echo "=== MENU PRINCIPAL ==="
    echo "Escolha uma opção:"
    echo "1. Ver status dos agentes"
    echo "2. Reconfigurar Wazuh Agent"
    echo "3. Reconfigurar Zabbix Agent"
    echo "4. Reiniciar serviços"
    echo "5. Sair"
    echo
    read -p "Opção (1-5): " MAIN_CHOICE
}

# =========================================
# LOOP PRINCIPAL
# =========================================
while true; do
    show_menu
    
    case $MAIN_CHOICE in
        1)
            show_agents_status
            ;;
        2)
            change_wazuh_config
            ;;
        3)
            change_zabbix_config
            ;;
        4)
            restart_services
            ;;
        5)
            echo
            echo "Saindo do gerenciador..."
            exit 0
            ;;
        *)
            echo "❌ Opção inválida. Tente novamente."
            ;;
    esac
    
    echo
    read -p "Pressione ENTER para continuar..."
done
