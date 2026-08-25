#!/bin/bash

# ==========================================
# Advanced FRP Multi-Protocol Tunnel Manager v1.5.0
# Supports: TCP | KCP | QUIC | WebSocket
# Prefixes: tcp_ / kcp_ / quic_ / ws_  (no conflict)
# FRP Version: 0.71.0
# ==========================================

VERSION="1.5.0-multi"
FRP_VERSION="0.71.0"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
DEFAULTS_FILE="/etc/frp/multi_defaults.conf"

# Colors
RED='\033[0;31m'
LIGHT_RED='\033[1;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE_LIGHT='\033[38;5;214m'
ORANGE='\033[38;5;208m'
NC='\033[0m'

# Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root.${NC}"
  exit 1
fi

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# Load or create defaults
load_defaults() {
    if [ -f "$DEFAULTS_FILE" ]; then
        source "$DEFAULTS_FILE"
    else
        DEFAULT_MAX_POOL_COUNT=50
        DEFAULT_POOL_COUNT=25
        DEFAULT_TOKEN_LENGTH=16
        DEFAULT_PORT_RANGE_START=40000
        DEFAULT_PORT_RANGE_END=65000
        save_defaults
    fi
}

save_defaults() {
    cat << EOF > "$DEFAULTS_FILE"
DEFAULT_MAX_POOL_COUNT=${DEFAULT_MAX_POOL_COUNT:-50}
DEFAULT_POOL_COUNT=${DEFAULT_POOL_COUNT:-25}
DEFAULT_TOKEN_LENGTH=${DEFAULT_TOKEN_LENGTH:-16}
DEFAULT_PORT_RANGE_START=${DEFAULT_PORT_RANGE_START:-40000}
DEFAULT_PORT_RANGE_END=${DEFAULT_PORT_RANGE_END:-65000}
EOF
}

# Print Logo
show_logo() {
    clear
    echo -e "${CYAN}"
    echo '  ______ _____  _____    _______ _   _ _   _ _   _ ______ _      '
    echo ' |  ____|  __ \|  __ \  |__   __| | | | \ | | \ | |  ____| |     '
    echo ' | |__  | |__) | |__) |    | |  | | | |  \| |  \| | |__  | |     '
    echo ' |  __| |  _  /|  ___/     | |  | | | | . ` | . ` |  __| | |     '
    echo ' | |    | | \ \| |         | |  | |_| | |\  | |\  | |____| |____ '
    echo ' |_|    |_|  \_\_|         |_|   \___/|_| \_|_| \_|______|______|'
    echo -e "${YELLOW}     -- Multi-Protocol Tunnel Manager v${VERSION} --${NC}"
    echo -e "${CYAN}          TCP | KCP | QUIC | WebSocket${NC}\n"
}

# Location Auto Detection
detect_location() {
    if [ -z "$SERVER_MODE" ]; then
        COUNTRY_CODE=$(curl -s --max-time 3 http://ip-api.com/line/?fields=countryCode 2>/dev/null)
        if [ -z "$COUNTRY_CODE" ]; then
            COUNTRY_CODE=$(curl -s --max-time 3 https://myip.wtf/json 2>/dev/null | grep -o '"countryCode": "[^"]*' | grep -o '[^"]*$')
        fi
        if [ -z "$COUNTRY_CODE" ]; then
            COUNTRY_CODE=$(curl -s --max-time 3 https://ifconfig.co/country-iso 2>/dev/null)
        fi

        if [ "$COUNTRY_CODE" == "IR" ]; then
            SERVER_MODE="IRAN"
        else
            SERVER_MODE="KHAREJ"
        fi
    fi
}

get_editor() {
    if command -v nano >/dev/null 2>&1; then echo "nano";
    elif command -v vim >/dev/null 2>&1; then echo "vim";
    else echo "vi"; fi
}

allow_ufw_port() {
    local port=$1
    local proto=${2:-tcp}
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$port"/"$proto" >/dev/null 2>&1
            echo -e "${GREEN}[UFW] Port $port/$proto added to whitelist.${NC}"
        fi
    fi
}

generate_token() {
    local len=${1:-16}
    tr -dc A-Za-z0-9 </dev/urandom | head -c "$len"
}

generate_random_port() {
    shuf -i ${DEFAULT_PORT_RANGE_START:-40000}-${DEFAULT_PORT_RANGE_END:-65000} -n 1
}

# Select Protocol
select_protocol() {
    echo -e "\n${CYAN}Select Protocol:${NC}"
    echo -e "  1) TCP          (Best pure performance)"
    echo -e "  2) KCP          (Good for lossy networks)"
    echo -e "  3) QUIC         (Modern + good bandwidth)"
    echo -e "  4) WebSocket    (Bypass firewall/proxy)"
    read -p "Choose [1-4]: " PROTO_CHOICE

    case $PROTO_CHOICE in
        1) PROTOCOL="tcp"; PROTO_NAME="TCP"; PROTO_COLOR="$CYAN" ;;
        2) PROTOCOL="kcp"; PROTO_NAME="KCP"; PROTO_COLOR="$PURPLE" ;;
        3) PROTOCOL="quic"; PROTO_NAME="QUIC"; PROTO_COLOR="$BLUE" ;;
        4) PROTOCOL="ws"; PROTO_NAME="WebSocket"; PROTO_COLOR="$GREEN" ;;
        *) echo -e "${RED}Invalid choice, defaulting to TCP${NC}"; PROTOCOL="tcp"; PROTO_NAME="TCP"; PROTO_COLOR="$CYAN" ;;
    esac
    echo -e "${GREEN}Selected Protocol: ${PROTO_COLOR}${PROTO_NAME}${NC}"
}

# ========== 1. Install Dependencies & FRP ==========
install_dependencies_and_frp() {
    show_logo
    echo -e "${YELLOW}[1/3] Installing Dependencies...${NC}"
    apt-get update -y
    apt-get install -y curl wget tar iperf3 ufw bc cron netcat-openbsd nano psmisc python3

    echo -e "${YELLOW}[2/3] Downloading FRP v${FRP_VERSION}...${NC}"
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; return ;;
    esac

    TMP_DIR="/tmp/frp_install_multi"
    mkdir -p "$TMP_DIR"
    wget -q --show-progress "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH_TYPE}.tar.gz" -O "$TMP_DIR/frp.tar.gz"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to download FRP.${NC}"
        rm -rf "$TMP_DIR"
        read -p "Press Enter to return..."
        return
    fi

    tar -zxvf "$TMP_DIR/frp.tar.gz" -C "$TMP_DIR"
    cp "$TMP_DIR/frp_${FRP_VERSION}_linux_${ARCH_TYPE}/frps" /usr/local/bin/
    cp "$TMP_DIR/frp_${FRP_VERSION}_linux_${ARCH_TYPE}/frpc" /usr/local/bin/
    chmod +x /usr/local/bin/frps /usr/local/bin/frpc
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}[3/3] FRP v${FRP_VERSION} installed successfully!${NC}"
    echo -e "${CYAN}Note: Binary is shared. Each protocol uses its own prefix (tcp_/kcp_/quic_/ws_).${NC}"
    read -p "Press Enter to return..."
}

# ========== Set Default Values ==========
set_default_values() {
    show_logo
    load_defaults
    echo -e "${CYAN}--- Set Default Values ---${NC}\n"
    echo -e "Current defaults:"
    echo -e "  Max Pool Count (Server) : ${YELLOW}${DEFAULT_MAX_POOL_COUNT}${NC}"
    echo -e "  Pool Count (Client)     : ${YELLOW}${DEFAULT_POOL_COUNT}${NC}"
    echo -e "  Token Length            : ${YELLOW}${DEFAULT_TOKEN_LENGTH}${NC}"
    echo -e "  Port Range              : ${YELLOW}${DEFAULT_PORT_RANGE_START}-${DEFAULT_PORT_RANGE_END}${NC}\n"

    read -p "Enter Max Pool Count for Server [current: $DEFAULT_MAX_POOL_COUNT]: " input
    DEFAULT_MAX_POOL_COUNT=${input:-$DEFAULT_MAX_POOL_COUNT}

    read -p "Enter Pool Count for Client [current: $DEFAULT_POOL_COUNT]: " input
    DEFAULT_POOL_COUNT=${input:-$DEFAULT_POOL_COUNT}

    read -p "Enter Token Length [current: $DEFAULT_TOKEN_LENGTH]: " input
    DEFAULT_TOKEN_LENGTH=${input:-$DEFAULT_TOKEN_LENGTH}

    read -p "Enter Port Range Start [current: $DEFAULT_PORT_RANGE_START]: " input
    DEFAULT_PORT_RANGE_START=${input:-$DEFAULT_PORT_RANGE_START}

    read -p "Enter Port Range End [current: $DEFAULT_PORT_RANGE_END]: " input
    DEFAULT_PORT_RANGE_END=${input:-$DEFAULT_PORT_RANGE_END}

    save_defaults
    echo -e "\n${GREEN}Default values saved successfully!${NC}"
    read -p "Press Enter to return..."
}

# ========== 2. Setup Server (Iran) ==========
setup_frps() {
    show_logo
    load_defaults
    select_protocol

    echo -e "\n${ORANGE}--- Setup FRP ${PROTO_NAME} Server (Iran / Inbound) ---${NC}\n"
    echo -e "${CYAN}Important: It is better to use the same tunnel number on both Iran and Kharej servers${NC}"
    echo -e "${CYAN}(Example: If you choose tunnel 10 on Iran, choose tunnel 10 on Kharej as well)${NC}\n"
    
    read -p "Enter Tunnel Index Number (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    read -p "Enter Tunnel Name (e.g. nl1, de2): " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"tunnel${ID}"}

    echo -e "\n${ORANGE}Choose configuration mode:${NC}"
    echo -e "  1) Use Defaults (recommended)"
    echo -e "  2) Manual / Custom values"
    read -p "Select [1-2]: " MODE
    MODE=${MODE:-1}

    if [ "$MODE" == "1" ]; then
        BIND_PORT=$(generate_random_port)
        AUTH_TOKEN=$(generate_token "$DEFAULT_TOKEN_LENGTH")
        MAX_POOL=$DEFAULT_MAX_POOL_COUNT
        echo -e "${GREEN}Using defaults → Port: $BIND_PORT | Token: $AUTH_TOKEN | maxPoolCount: $MAX_POOL${NC}"
    else
        RANDOM_BIND=$(generate_random_port)
        read -p "Enter Bind Port [Suggested: $RANDOM_BIND]: " BIND_PORT
        BIND_PORT=${BIND_PORT:-$RANDOM_BIND}
        
        DEFAULT_TOKEN=$(generate_token "$DEFAULT_TOKEN_LENGTH")
        read -p "Enter Authentication Token [Auto: $DEFAULT_TOKEN]: " AUTH_TOKEN
        AUTH_TOKEN=${AUTH_TOKEN:-$DEFAULT_TOKEN}

        read -p "Enter transport.maxPoolCount [Default: $DEFAULT_MAX_POOL_COUNT]: " MAX_POOL
        MAX_POOL=${MAX_POOL:-$DEFAULT_MAX_POOL_COUNT}
    fi

    CONF_FILE="$CONFIG_DIR/frps_${PROTOCOL}_tunnel${ID}.toml"

    case $PROTOCOL in
        tcp|ws)
            cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = $PROTO_NAME
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.maxPoolCount = $MAX_POOL
EOF
            allow_ufw_port "$BIND_PORT" "tcp"
            ;;
        kcp)
            cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = $PROTO_NAME
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
kcpBindPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.maxPoolCount = $MAX_POOL
EOF
            allow_ufw_port "$BIND_PORT" "udp"
            allow_ufw_port "$BIND_PORT" "tcp"
            ;;
        quic)
            cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = $PROTO_NAME
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
quicBindPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.maxPoolCount = $MAX_POOL
EOF
            allow_ufw_port "$BIND_PORT" "udp"
            allow_ufw_port "$BIND_PORT" "tcp"
            ;;
    esac

    SERVICE_FILE="/etc/systemd/system/frps_${PROTOCOL}_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP ${PROTO_NAME} Server Tunnel ${ID} (${TUNNEL_NAME})
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c $CONF_FILE
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "frps_${PROTOCOL}_tunnel${ID}.service"

    MY_IP=$(curl -s --max-time 3 http://ip-api.com/line/?fields=query 2>/dev/null)

    echo -e "\n${ORANGE}================ ${PROTO_NAME} SERVER (IRAN) CREATED SUCCESSFULLY ================${NC}"
    echo -e "Tunnel ID     : ${ORANGE}${ID}${NC}"
    echo -e "Tunnel Name   : ${ORANGE}${TUNNEL_NAME}${NC}"
    echo -e "Protocol      : ${PROTO_COLOR}${PROTO_NAME}${NC}"
    echo -e "Server IP     : ${CYAN}${MY_IP}${NC}"
    echo -e "Bind Port     : ${CYAN}${BIND_PORT}${NC}"
    echo -e "Auth Token    : ${CYAN}${AUTH_TOKEN}${NC}"
    echo -e "maxPoolCount  : ${CYAN}${MAX_POOL}${NC}"
    echo -e "${ORANGE}==============================================================================${NC}\n"

    read -p "Press Enter to return..."
}

# ========== 3. Setup Client (Kharej) ==========
setup_frpc() {
    show_logo
    load_defaults
    select_protocol

    echo -e "\n${YELLOW}--- Setup FRP ${PROTO_NAME} Client (Kharej / Outbound) ---${NC}\n"
    echo -e "${CYAN}Important: It is better to use the same tunnel number on both Iran and Kharej servers${NC}"
    echo -e "${CYAN}(Example: If you choose tunnel 10 on Iran, choose tunnel 10 on Kharej as well)${NC}\n"
    
    read -p "Enter Tunnel Index Number (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    read -p "Enter Tunnel Name (e.g. nl1, de2): " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"tunnel${ID}"}

    read -p "Enter Iran Server IP or Domain: " IRAN_IP
    read -p "Enter FRP Server Bind Port: " BIND_PORT
    read -p "Enter Authentication Token: " AUTH_TOKEN

    echo -e "\n${YELLOW}Choose configuration mode:${NC}"
    echo -e "  1) Use Defaults (recommended)"
    echo -e "  2) Manual / Custom values"
    read -p "Select [1-2]: " MODE
    MODE=${MODE:-1}

    if [ "$MODE" == "1" ]; then
        POOL_COUNT=$DEFAULT_POOL_COUNT
        echo -e "${GREEN}Using default poolCount: $POOL_COUNT${NC}"
    else
        read -p "Enter transport.poolCount [Default: $DEFAULT_POOL_COUNT]: " POOL_COUNT
        POOL_COUNT=${POOL_COUNT:-$DEFAULT_POOL_COUNT}
    fi

    case $PROTOCOL in
        tcp)  IPERF_PORT=$((55109 + ID)) ;;
        kcp)  IPERF_PORT=$((55209 + ID)) ;;
        quic) IPERF_PORT=$((55409 + ID)) ;;
        ws)   IPERF_PORT=$((55309 + ID)) ;;
    esac

    echo -e "${YELLOW}Enter local ports to forward separated by comma (e.g. 443,80,8443):${NC}"
    read -p "Ports: " PORTS_INPUT

    CONF_FILE="$CONFIG_DIR/frpc_${PROTOCOL}_tunnel${ID}.toml"

    cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = $PROTO_NAME
serverAddr = "$IRAN_IP"
serverPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.poolCount = $POOL_COUNT
EOF

    case $PROTOCOL in
        tcp)
            ;;
        kcp)
            echo 'transport.protocol = "kcp"' >> "$CONF_FILE"
            ;;
        quic)
            echo 'transport.protocol = "quic"' >> "$CONF_FILE"
            ;;
        ws)
            echo 'transport.protocol = "websocket"' >> "$CONF_FILE"
            ;;
    esac

    cat << EOF >> "$CONF_FILE"

# iperf3 SpeedTest Port Auto-Added
[[proxies]]
name = "${TUNNEL_NAME}_iperf3_${IPERF_PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $IPERF_PORT
remotePort = $IPERF_PORT

EOF

    IFS=',' read -ra ADDR <<< "$PORTS_INPUT"
    for PORT in "${ADDR[@]}"; do
        PORT=$(echo "$PORT" | xargs)
        if [ -n "$PORT" ]; then
            cat << EOF >> "$CONF_FILE"
[[proxies]]
name = "${TUNNEL_NAME}_tcp_${PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT

EOF
            allow_ufw_port "$PORT"
        fi
    done

    allow_ufw_port "$IPERF_PORT"

    SERVICE_FILE="/etc/systemd/system/frpc_${PROTOCOL}_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP ${PROTO_NAME} Client Tunnel ${ID} (${TUNNEL_NAME})
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c $CONF_FILE
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "frpc_${PROTOCOL}_tunnel${ID}.service"

    echo -e "\n${YELLOW}FRP ${PROTO_NAME} Client Tunnel ${ID} (${TUNNEL_NAME}) created successfully!${NC}"
    echo -e "poolCount used: ${CYAN}${POOL_COUNT}${NC}"
    read -p "Press Enter to return..."
}

# ========== List All Tunnels ==========
list_tunnels() {
    echo -e "${PURPLE}--- Active Configured Tunnels (All Protocols) ---${NC}"
    for proto in tcp kcp quic ws; do
        for i in {1..10}; do
            S_CONF="$CONFIG_DIR/frps_${proto}_tunnel${i}.toml"
            C_CONF="$CONFIG_DIR/frpc_${proto}_tunnel${i}.toml"
            
            if [ -f "$S_CONF" ]; then
                NAME=$(grep "Tunnel_Name" "$S_CONF" | cut -d'"' -f2)
                BIND=$(grep -E "bindPort|kcpBindPort|quicBindPort" "$S_CONF" | head -1 | awk '{print $3}')
                STATUS=$(systemctl is-active "frps_${proto}_tunnel${i}.service" 2>/dev/null)
                if [ "$STATUS" == "active" ]; then ST_TXT="${GREEN}ONLINE${NC}"; else ST_TXT="${RED}OFFLINE${NC}"; fi
                echo -e "Tunnel $i [${ORANGE}${proto^^} Server / IRAN${NC} | Name: ${CYAN}${NAME:-N/A}${NC}] Status: [$ST_TXT] | Port: ${YELLOW}${BIND:-N/A}${NC}"
            elif [ -f "$C_CONF" ]; then
                NAME=$(grep "Tunnel_Name" "$C_CONF" | cut -d'"' -f2)
                PORTS=$(grep "remotePort" "$C_CONF" | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')
                STATUS=$(systemctl is-active "frpc_${proto}_tunnel${i}.service" 2>/dev/null)
                if [ "$STATUS" == "active" ]; then ST_TXT="${GREEN}ONLINE${NC}"; else ST_TXT="${RED}OFFLINE${NC}"; fi
                echo -e "Tunnel $i [${YELLOW}${proto^^} Client / KHAREJ${NC} | Name: ${CYAN}${NAME:-N/A}${NC}] Status: [$ST_TXT] | Ports: ${YELLOW}[${PORTS:-N/A}]${NC}"
            fi
        done
    done
    echo "---------------------------------"
}

# ========== Health Check ==========
check_tunnel_health() {
    show_logo
    echo -e "${CYAN}--- Active Tunnel Connectivity Test ---${NC}"
    select_protocol
    read -p "Enter Tunnel Index (1 to 10): " ID
    
    C_CONF="$CONFIG_DIR/frpc_${PROTOCOL}_tunnel${ID}.toml"
    S_CONF="$CONFIG_DIR/frps_${PROTOCOL}_tunnel${ID}.toml"

    if [ -f "$C_CONF" ]; then
        IRAN_IP=$(grep "serverAddr" "$C_CONF" | cut -d'"' -f2)
        SERVER_PORT=$(grep "serverPort" "$C_CONF" | awk '{print $3}')
        echo -e "${YELLOW}Testing ${PROTO_NAME} connection from Kharej to Iran ($IRAN_IP:$SERVER_PORT)...${NC}"
        
        if [ "$PROTOCOL" == "kcp" ] || [ "$PROTOCOL" == "quic" ]; then
            nc -zu -w 5 "$IRAN_IP" "$SERVER_PORT" 2>/dev/null
        else
            nc -z -w 5 "$IRAN_IP" "$SERVER_PORT" 2>/dev/null
        fi
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[SUCCESS] Connectivity looks good.${NC}"
        else
            echo -e "${RED}[FAILED] Cannot reach Iran server port $SERVER_PORT.${NC}"
        fi

    elif [ -f "$S_CONF" ]; then
        BIND=$(grep -E "bindPort|kcpBindPort|quicBindPort" "$S_CONF" | head -1 | awk '{print $3}')
        echo -e "${ORANGE}Testing local ${PROTO_NAME} Server on port $BIND...${NC}"
        
        if [ "$PROTOCOL" == "kcp" ] || [ "$PROTOCOL" == "quic" ]; then
            if ss -ulnp | grep -q ":$BIND "; then
                echo -e "${GREEN}[SUCCESS] Server is ONLINE (UDP).${NC}"
            else
                echo -e "${RED}[FAILED] Port $BIND not responding.${NC}"
            fi
        else
            nc -z -w 3 127.0.0.1 "$BIND" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[SUCCESS] Server is ONLINE.${NC}"
            else
                echo -e "${RED}[FAILED] Port $BIND not responding.${NC}"
            fi
        fi
    else
        echo -e "${RED}Tunnel $ID (${PROTO_NAME}) is not configured on this server!${NC}"
    fi

    read -p "Press Enter to return..."
}

# ========== Manage Tunnels ==========
manage_tunnels() {
    show_logo
    list_tunnels
    echo -e "${CYAN}1. Restart Tunnel${NC}"
    echo -e "${CYAN}2. Stop Tunnel${NC}"
    echo -e "${CYAN}3. View Logs${NC}"
    echo -e "${CYAN}4. Edit Config Manually${NC}"
    echo -e "${LIGHT_RED}5. Delete Tunnel${NC}"
    echo -e "${CYAN}6. Set Auto-Restart Schedule${NC}"
    echo -e "${CYAN}0. Back${NC}"
    read -p "Select choice: " ACT
    
    if [ "$ACT" == "0" ]; then return; fi

    select_protocol
    read -p "Enter Tunnel Index (1-10): " ID

    S_SVC="frps_${PROTOCOL}_tunnel${ID}.service"
    C_SVC="frpc_${PROTOCOL}_tunnel${ID}.service"
    SVC=""
    [ -f "/etc/systemd/system/$S_SVC" ] && SVC="$S_SVC"
    [ -f "/etc/systemd/system/$C_SVC" ] && SVC="$C_SVC"

    if [ -z "$SVC" ]; then
        echo -e "${RED}Tunnel $ID (${PROTO_NAME}) not found!${NC}"
        sleep 2; return
    fi

    case $ACT in
        1) systemctl restart "$SVC"; echo -e "${GREEN}Tunnel restarted.${NC}" ;;
        2) systemctl stop "$SVC"; echo -e "${YELLOW}Tunnel stopped.${NC}" ;;
        3) journalctl -u "$SVC" -n 50 --no-pager ;;
        4)
            CONF=""
            [ -f "$CONFIG_DIR/frps_${PROTOCOL}_tunnel${ID}.toml" ] && CONF="$CONFIG_DIR/frps_${PROTOCOL}_tunnel${ID}.toml"
            [ -f "$CONFIG_DIR/frpc_${PROTOCOL}_tunnel${ID}.toml" ] && CONF="$CONFIG_DIR/frpc_${PROTOCOL}_tunnel${ID}.toml"
            if [ -n "$CONF" ]; then
                $(get_editor) "$CONF"
                systemctl restart "$SVC"
                echo -e "${GREEN}Config updated and service restarted.${NC}"
            fi
            ;;
        5)
            echo -e "${LIGHT_RED}WARNING: This will permanently delete the tunnel!${NC}"
            read -p "Type 'yes' to confirm: " CONFIRM
            if [ "$CONFIRM" == "yes" ]; then
                systemctl disable --now "$SVC"
                rm -f "/etc/systemd/system/$SVC"
                rm -f "$CONFIG_DIR/frps_${PROTOCOL}_tunnel${ID}.toml" "$CONFIG_DIR/frpc_${PROTOCOL}_tunnel${ID}.toml"
                systemctl daemon-reload
                echo -e "${LIGHT_RED}Tunnel deleted.${NC}"
            else
                echo -e "${YELLOW}Cancelled.${NC}"
            fi
            ;;
        6)
            read -p "Enter restart interval in hours: " HRS
            (crontab -l 2>/dev/null; echo "0 */$HRS * * * systemctl restart $SVC") | crontab -
            echo -e "${GREEN}Auto-restart set every $HRS hours.${NC}"
            ;;
    esac
    read -p "Press Enter to continue..."
}

# ========== Speedtest ==========
run_speedtest() {
    show_logo
    echo -e "${CYAN}--- Bandwidth SpeedTest Module ---${NC}\n"
    echo -e "${YELLOW}Important: First run Option 1 (Server Mode) on Kharej server,${NC}"
    echo -e "${YELLOW}then run Option 2 (Client Test) on Iran server.${NC}\n"

    select_protocol
    read -p "Enter Tunnel Index (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid ID!${NC}"; sleep 2; return
    fi

    case $PROTOCOL in
        tcp)  DEFAULT_PORT=$((55109 + ID)) ;;
        kcp)  DEFAULT_PORT=$((55209 + ID)) ;;
        quic) DEFAULT_PORT=$((55409 + ID)) ;;
        ws)   DEFAULT_PORT=$((55309 + ID)) ;;
    esac

    echo -e "${YELLOW}Default iperf3 port for this tunnel: ${DEFAULT_PORT}${NC}\n"
    echo "1. Run iperf3 Server Mode (Run this first on Kharej)"
    echo "2. Run iperf3 Client Test (Run this later on Iran)"
    read -p "Select option: " TEST_OPT

    if [ "$TEST_OPT" == "1" ]; then
        allow_ufw_port "$DEFAULT_PORT"
        fuser -k "${DEFAULT_PORT}/tcp" >/dev/null 2>&1
        echo -e "${GREEN}Starting iperf3 server on port $DEFAULT_PORT... (CTRL+C to stop)${NC}"
        iperf3 -s -p "$DEFAULT_PORT"
    elif [ "$TEST_OPT" == "2" ]; then
        read -p "Enter target port [Default: $DEFAULT_PORT]: " TARGET_PORT
        TARGET_PORT=${TARGET_PORT:-$DEFAULT_PORT}

        echo -e "\n1) 5s  2) 10s  3) Custom"
        read -p "Duration: " DUR_OPT
        case $DUR_OPT in
            1) DURATION=5 ;;
            2) DURATION=10 ;;
            3) read -p "Seconds: " DURATION; DURATION=${DURATION:-10} ;;
            *) DURATION=10 ;;
        esac

        echo -e "\n${YELLOW}Testing through ${PROTO_NAME} tunnel...${NC}"
        RAW_JSON=$(iperf3 -c 127.0.0.1 -p "$TARGET_PORT" -P 8 -t "$DURATION" --json 2>/dev/null)
        
        if [ -z "$RAW_JSON" ]; then
            echo -e "${RED}[ERROR] Failed! Make sure Server mode is running on Kharej first.${NC}"
        else
            MBPS=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    bps = data["end"]["sum_received"]["bits_per_second"]
    print(f"{bps / 1e6:.2f}")
except:
    try:
        bps = data["end"]["sum_sent"]["bits_per_second"]
        print(f"{bps / 1e6:.2f}")
    except:
        print("0")
' "$RAW_JSON" 2>/dev/null)

            if [ -n "$MBPS" ] && [ "$MBPS" != "0" ]; then
                echo -e "\n${GREEN}================ SPEEDTEST RESULTS ================${NC}"
                echo -e "Protocol       : ${PROTO_COLOR}${PROTO_NAME}${NC}"
                echo -e "Tunnel ID      : ${ORANGE}${ID}${NC}"
                echo -e "Throughput     : ${CYAN}${MBPS} Mbps${NC}"
                echo -e "${GREEN}===================================================${NC}\n"
            else
                echo -e "${RED}Failed to parse results.${NC}"
            fi
        fi
    fi
    read -p "Press Enter to return..."
}

# ========== Optimize System ==========
optimize_system() {
    show_logo
    echo -e "${CYAN}--- System Optimization ---${NC}\n"
    echo "1) Optimize for TCP / WebSocket (BBR + TCP buffers)"
    echo "2) Optimize for KCP / QUIC (UDP buffers)"
    echo "3) Both"
    read -p "Select: " OPT

    if [ "$OPT" == "1" ] || [ "$OPT" == "3" ]; then
        cat << EOF > /etc/sysctl.d/99-frp-tcp.conf
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF
        sysctl -p /etc/sysctl.d/99-frp-tcp.conf >/dev/null 2>&1
        echo -e "${GREEN}TCP/BBR optimized.${NC}"
    fi

    if [ "$OPT" == "2" ] || [ "$OPT" == "3" ]; then
        cat << EOF > /etc/sysctl.d/99-frp-udp.conf
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.netdev_max_backlog = 5000
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.udp_mem = 8388608 12582912 16777216
EOF
        sysctl -p /etc/sysctl.d/99-frp-udp.conf >/dev/null 2>&1
        echo -e "${GREEN}UDP buffers optimized.${NC}"
    fi

    echo -e "${YELLOW}Recommendation: Restart services or reboot for full effect.${NC}"
    read -p "Press Enter to return..."
}

# ========== Main Menu ==========
main_menu() {
    detect_location
    load_defaults
    while true; do
        show_logo
        echo -e "Server Location Status: ${YELLOW}[ ${SERVER_MODE} ]${NC}"
        echo -e "FRP Version: ${GREEN}v${FRP_VERSION}${NC} | Protocols: ${CYAN}TCP · KCP · QUIC · WS${NC}\n"
        
        list_tunnels

        echo -e "${CYAN}1. Install Dependencies & FRP v${FRP_VERSION}${NC}"
        echo -e "${ORANGE}2. Setup Server (Iran)${NC}"
        echo -e "${YELLOW}3. Setup Client (Kharej)${NC}"
        echo -e "${CYAN}4. Check Tunnel Health${NC}"
        echo -e "${CYAN}5. Manage / Restart / Logs / Delete Tunnels${NC}"
        echo -e "${CYAN}6. Run iperf3 Speedtest${NC}"
        echo -e "${CYAN}7. Change Location Mode (Toggle Iran/Kharej)${NC}"
        echo -e "${CYAN}8. Set Default Values${NC}"
        echo -e "${CYAN}9. Optimize System (TCP/BBR or UDP)${NC}"
        echo -e "${LIGHT_RED}0. Exit${NC}"
        echo "---------------------------------"
        read -p "Choose an option: " OPT

        case $OPT in
            1) install_dependencies_and_frp ;;
            2) setup_frps ;;
            3) setup_frpc ;;
            4) check_tunnel_health ;;
            5) manage_tunnels ;;
            6) run_speedtest ;;
            7) 
                if [ "$SERVER_MODE" == "IRAN" ]; then SERVER_MODE="KHAREJ"; else SERVER_MODE="IRAN"; fi
                ;;
            8) set_default_values ;;
            9) optimize_system ;;
            0) echo -e "${LIGHT_RED}Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
