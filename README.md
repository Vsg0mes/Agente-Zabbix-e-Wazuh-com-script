# Instalar-o-agente-Zabbix-e-Wazuh-com-script

Script Bash para **instalação automática** do **Zabbix Agent (ou Agent2)** e do **Wazuh Agent** em servidores Ubuntu, com **TLS via certificados colados diretamente no terminal**.

Projetado para ambientes de produção, VMs e cloud.

---

## ✅ Funcionalidades

- Instala **Zabbix Agent ou Zabbix Agent2**
- Instala **Wazuh Agent**
- Usa **um único IP** para:
  - Zabbix Server
  - Wazuh Manager
- Configuração completa de **TLS**
- Certificados colados via **ENTER (ENTER ENTER)**  
  (compatível com consoles de VM)
- Detecta automaticamente:
  - Versão do Ubuntu (20.04 / 22.04 / 24.04)
  - Arquitetura do sistema (amd64 / arm64)
- Não depende de arquivos locais de certificado

---

## 🖥️ Sistemas suportados

- Ubuntu Server 20.04 LTS  
- Ubuntu Server 22.04 LTS  
- Ubuntu Server 24.04 LTS  

---

## 📦 O que será instalado

- Zabbix Agent **ou** Zabbix Agent2
- Wazuh Agent (versão 4.14.0)
- Configuração TLS completa para ambos

---

## 🚀 Como usar

### 1. Clonar o repositório
```bash
git clone https://github.com/<seu-usuario>/install-zabbix-wazuh.git
```
### Dar permissão de execução
```bash
chmod +x install_wazuh_zabbix_master.sh
```
### Executar o script
```bash
sudo ./install_wazuh_zabbix_master.sh
