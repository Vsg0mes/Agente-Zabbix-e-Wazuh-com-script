#!/bin/bash

# =========================================
# Desinstalador Wazuh Agent e Zabbix Agent
# =========================================

set -euo pipefail

TARGET=""
PURGE_CONFIG=false
ASSUME_YES=false

print_usage() {
    cat <<'EOF'
Uso:
  sudo ./uninstall_wazuh_zabbix_agents.sh [opcoes]

Opcoes:
  --target <wazuh|zabbix|all>  Define qual agente remover.
  --purge-config               Remove tambem arquivos/diretorios residuais.
  --yes                        Nao pede confirmacao.
  -h, --help                   Mostra esta ajuda.

Sem --target, o script abre menu interativo.
EOF
}

log() {
    echo "[INFO] $1"
}

warn() {
    echo "[AVISO] $1"
}

err() {
    echo "[ERRO] $1"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Execute com sudo/root."
        exit 1
    fi
}

is_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

stop_disable_service_if_exists() {
    local service_name="$1"
    if systemctl list-unit-files | grep -q "^${service_name}\.service"; then
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
    fi
}

confirm_or_exit() {
    if [[ "$ASSUME_YES" == true ]]; then
        return
    fi

    echo
    read -r -p "Confirma a desinstalacao? (s/n): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        log "Operacao cancelada."
        exit 0
    fi
}

uninstall_wazuh() {
    echo
    log "Iniciando desinstalacao do Wazuh Agent..."

    if ! is_pkg_installed "wazuh-agent"; then
        warn "Pacote wazuh-agent nao esta instalado."
        return
    fi

    stop_disable_service_if_exists "wazuh-agent"

    if apt-get purge -y wazuh-agent; then
        log "Pacote wazuh-agent removido."
    else
        warn "Falha no apt-get purge, tentando dpkg --purge."
        dpkg --purge wazuh-agent 2>/dev/null || true
    fi

    apt-get autoremove -y 2>/dev/null || true

    if [[ "$PURGE_CONFIG" == true ]]; then
        rm -rf /var/ossec 2>/dev/null || true
        log "Diretorio /var/ossec removido."
    fi
}

uninstall_zabbix() {
    local pkgs=()

    if is_pkg_installed "zabbix-agent"; then
        pkgs+=("zabbix-agent")
    fi
    if is_pkg_installed "zabbix-agent2"; then
        pkgs+=("zabbix-agent2")
    fi

    echo
    log "Iniciando desinstalacao do Zabbix Agent..."

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        warn "Nenhum pacote zabbix-agent/zabbix-agent2 instalado."
        return
    fi

    stop_disable_service_if_exists "zabbix-agent"
    stop_disable_service_if_exists "zabbix-agent2"

    if apt-get purge -y "${pkgs[@]}"; then
        log "Pacotes removidos: ${pkgs[*]}"
    else
        warn "Falha no apt-get purge, tentando dpkg --purge."
        for pkg in "${pkgs[@]}"; do
            dpkg --purge "$pkg" 2>/dev/null || true
        done
    fi

    apt-get autoremove -y 2>/dev/null || true

    if [[ "$PURGE_CONFIG" == true ]]; then
        rm -rf /etc/zabbix/ssl 2>/dev/null || true
        rm -f /etc/zabbix/zabbix_agentd.conf* 2>/dev/null || true
        rm -f /etc/zabbix/zabbix_agent2.conf* 2>/dev/null || true
        log "Arquivos residuais do Zabbix removidos."
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target)
                TARGET="${2:-}"
                shift 2
                ;;
            --purge-config)
                PURGE_CONFIG=true
                shift
                ;;
            --yes)
                ASSUME_YES=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                err "Opcao invalida: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

interactive_select_target() {
    echo "=== Desinstalador de Agentes ==="
    echo "1) Somente Wazuh Agent"
    echo "2) Somente Zabbix Agent"
    echo "3) Wazuh + Zabbix"
    echo
    read -r -p "Escolha (1-3): " OPTION

    case "$OPTION" in
        1) TARGET="wazuh" ;;
        2) TARGET="zabbix" ;;
        3) TARGET="all" ;;
        *)
            err "Opcao invalida."
            exit 1
            ;;
    esac

    read -r -p "Remover arquivos residuais de configuracao? (s/n): " CLEANUP
    if [[ "$CLEANUP" == "s" || "$CLEANUP" == "S" ]]; then
        PURGE_CONFIG=true
    fi
}

main() {
    require_root
    parse_args "$@"

    if [[ -z "$TARGET" ]]; then
        interactive_select_target
    fi

    case "$TARGET" in
        wazuh|zabbix|all) ;;
        *)
            err "Valor invalido para --target: $TARGET"
            print_usage
            exit 1
            ;;
    esac

    echo
    log "Resumo da execucao:"
    log "Target: $TARGET"
    log "Purge config: $PURGE_CONFIG"
    confirm_or_exit

    case "$TARGET" in
        wazuh)
            uninstall_wazuh
            ;;
        zabbix)
            uninstall_zabbix
            ;;
        all)
            uninstall_wazuh
            uninstall_zabbix
            ;;
    esac

    echo
    log "Processo finalizado."
}

main "$@"
