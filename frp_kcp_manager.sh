#!/bin/bash

# ==========================================
# Advanced FRP KCP Tunnel Manager v1.4.0
# Based on xTunnel_Bench logic + KCP optimizations
# Config/Service prefix: kcp  (no conflict with TCP/WS)
# FRP Version: 0.71.0
# ==========================================

VERSION="1.4.0-kcp"
FRP_VERSION="0.71.0"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
DEFAULTS_FILE="/etc/frp/kcp_defaults.conf"

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
        # Default values
        DEFAULT_MAX_POOL_COUNT=50
        DEFAULT_POOL_COUNT=20
        DEFAULT_TOKEN_LENGTH=16
        DEFAULT_PORT_RANGE_START=40000
        DEFAULT_PORT_RANGE_END=65000
        save_defaults
    fi
}

save_defaults() {
    cat << EOF > "$DEFAULTS_FILE"
DEFAULT_MAX_POOL_COUNT=${DEFAULT_MAX_POOL_COUNT:-50}
DEFAULT_POOL_COUNT=${DEFAULT_POOL_COUNT:-20}
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
    echo -e "${YELLOW}           -- KCP Multi-Tunnel Manager v${VERSION} --${NC}\n"
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

    TMP_DIR="/tmp/frp_install_kcp"
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
    echo -e "${CYAN}Note: Binary is shared (protocol-agnostic). KCP configs use 'kcp' prefix → no conflict with TCP/WS.${NC}"
    read -p "Press Enter to return..."
}

# ========== Separate Menu: Set Default Values ==========
set_default_values() {
    show_logo
    load_defaults
    echo -e "${CYAN}--- Set Default Values for KCP Setup ---${NC}\n"
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

# ========== 2. Setup FRP KCP Server (Iran) ==========
setup_frps() {
    show_logo
    load_defaults
    echo -e "${ORANGE}--- Setup FRP KCP Server (Iran / Inbound) ---${NC}\n"
    
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
        read -p "Enter FRP KCP Bind Port (UDP) [Suggested: $RANDOM_BIND]: " BIND_PORT
        BIND_PORT=${BIND_PORT:-$RANDOM_BIND}
        
        DEFAULT_TOKEN=$(generate_token "$DEFAULT_TOKEN_LENGTH")
        read -p "Enter Authentication Token [Auto: $DEFAULT_TOKEN]: " AUTH_TOKEN
        AUTH_TOKEN=${AUTH_TOKEN:-$DEFAULT_TOKEN}

        read -p "Enter transport.maxPoolCount [Default: $DEFAULT_MAX_POOL_COUNT]: " MAX_POOL
        MAX_POOL=${MAX_POOL:-$DEFAULT_MAX_POOL_COUNT}
    fi

    CONF_FILE="$CONFIG_DIR/frps_kcp_tunnel${ID}.toml"
    cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = KCP
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
kcpBindPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.maxPoolCount = $MAX_POOL
EOF

    SERVICE_FILE="/etc/systemd/system/frps_kcp_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP KCP Server Tunnel ${ID} (${TUNNEL_NAME})
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
    systemctl enable --now "frps_kcp_tunnel${ID}.service"
    allow_ufw_port "$BIND_PORT" "udp"
    allow_ufw_port "$BIND_PORT" "tcp"

    MY_IP=$(curl -s --max-time 3 http://ip-api.com/line/?fields=query 2>/dev/null)

    echo -e "\n${ORANGE}================ KCP SERVER (IRAN) CREATED SUCCESSFULLY ================${NC}"
    echo -e "Tunnel ID     : ${ORANGE}${ID}${NC}"
    echo -e "Tunnel Name   : ${ORANGE}${TUNNEL_NAME}${NC}"
    echo -e "Protocol      : ${CYAN}KCP (UDP)${NC}"
    echo -e "Server IP     : ${CYAN}${MY_IP}${NC}"
    echo -e "KCP Bind Port : ${CYAN}${BIND_PORT}${NC}"
    echo -e "Auth Token    : ${CYAN}${AUTH_TOKEN}${NC}"
    echo -e "maxPoolCount  : ${CYAN}${MAX_POOL}${NC}"
    echo -e "${ORANGE}========================================================================${NC}\n"

    read -p "Press Enter to return..."
}

# ========== 3. Setup FRP KCP Client (Kharej) ==========
setup_frpc() {
    show_logo
    load_defaults
    echo -e "${YELLOW}--- Setup FRP KCP Client (Kharej / Outbound) ---${NC}\n"
    
    read -p "Enter Tunnel Index Number (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    read -p "Enter Tunnel Name (e.g. nl1, de2): " TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-"tunnel${ID}"}

    read -p "Enter Iran Server IP or Domain: " IRAN_IP
    read -p "Enter FRP KCP Server Bind Port: " BIND_PORT
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

    IPERF_PORT=$((55209 + ID))
    echo -e "${YELLOW}Enter local ports to forward separated by comma (e.g. 443,80,8443):${NC}"
    read -p "Ports: " PORTS_INPUT

    CONF_FILE="$CONFIG_DIR/frpc_kcp_tunnel${ID}.toml"
    cat << EOF > "$CONF_FILE"
# Tunnel_Name = "$TUNNEL_NAME"
# Protocol   = KCP
serverAddr = "$IRAN_IP"
serverPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.protocol = "kcp"
transport.tcpMux = true
transport.poolCount = $POOL_COUNT

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

    SERVICE_FILE="/etc/systemd/system/frpc_kcp_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP KCP Client Tunnel ${ID} (${TUNNEL_NAME})
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
    systemctl enable --now "frpc_kcp_tunnel${ID}.service"

    echo -e "\n${YELLOW}FRP KCP Client Tunnel ${ID} (${TUNNEL_NAME}) created successfully!${NC}"
    echo -e "poolCount used: ${CYAN}${POOL_COUNT}${NC}"
    read -p "Press Enter to return..."
}

# ========== List Tunnels ==========
list_tunnels() {
    echo -e "${PURPLE}--- Active Configured KCP Tunnels ---${NC}"
    for i in {1..10}; do
        S_CONF="$CONFIG_DIR/frps_kcp_tunnel${i}.toml"
        C_CONF="$CONFIG_DIR/frpc_kcp_tunnel${i}.toml"
        
        if [ -f "$S_CONF" ]; then
            NAME=$(grep "Tunnel_Name" "$S_CONF" | cut -d'"' -f2)
            BIND=$(grep "kcpBindPort" "$S_CONF" | awk '{print $3}')
            STATUS=$(systemctl is-active "frps_kcp_tunnel${i}.service" 2>/dev/null)
            if [ "$STATUS" == "active" ]; then ST_TXT="${GREEN}ONLINE${NC}"; else ST_TXT="${RED}OFFLINE${NC}"; fi
            echo -e "Tunnel $i [${ORANGE}KCP Server / IRAN${NC} | Name: ${CYAN}${NAME:-N/A}${NC}] Status: [$ST_TXT] | KCP Port: ${YELLOW}${BIND:-N/A}${NC}"
            
        elif [ -f "$C_CONF" ]; then
            NAME=$(grep "Tunnel_Name" "$C_CONF" | cut -d'"' -f2)
            PORTS=$(grep "remotePort" "$C_CONF" | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')
            STATUS=$(systemctl is-active "frpc_kcp_tunnel${i}.service" 2>/dev/null)
            if [ "$STATUS" == "active" ]; then ST_TXT="${GREEN}ONLINE${NC}"; else ST_TXT="${RED}OFFLINE${NC}"; fi
            echo -e "Tunnel $i [${YELLOW}KCP Client / KHAREJ${NC} | Name: ${CYAN}${NAME:-N/A}${NC}] Status: [$ST_TXT] | Forwarded Ports: ${YELLOW}[${PORTS:-N/A}]${NC}"
        else
            echo -e "Tunnel $i: ${YELLOW}Not Configured${NC}"
        fi
    done
    echo "---------------------------------"
}

# ========== Health Check ==========
check_tunnel_health() {
    show_logo
    echo -e "${CYAN}--- Active KCP Tunnel Connectivity Test ---${NC}"
    read -p "Enter Tunnel Index (1 to 10): " ID
    
    C_CONF="$CONFIG_DIR/frpc_kcp_tunnel${ID}.toml"
    S_CONF="$CONFIG_DIR/frps_kcp_tunnel${ID}.toml"

    if [ -f "$C_CONF" ]; then
        IRAN_IP=$(grep "serverAddr" "$C_CONF" | cut -d'"' -f2)
        SERVER_PORT=$(grep "serverPort" "$C_CONF" | awk '{print $3}')
        echo -e "${YELLOW}Testing KCP connection from Kharej to Iran Server ($IRAN_IP:$SERVER_PORT UDP)...${NC}"
        
        nc -zu -w 5 "$IRAN_IP" "$SERVER_PORT" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[SUCCESS] UDP port is reachable. KCP tunnel connectivity looks good.${NC}"
        else
            echo -e "${RED}[FAILED] Cannot reach Iran server UDP port $SERVER_PORT (firewall or KCP issue).${NC}"
        fi

    elif [ -f "$S_CONF" ]; then
        BIND=$(grep "kcpBindPort" "$S_CONF" | awk '{print $3}')
        echo -e "${ORANGE}Testing local FRP KCP Server listener on UDP port $BIND...${NC}"
        
        if ss -ulnp | grep -q ":$BIND "; then
            echo -e "${GREEN}[SUCCESS] FRP KCP Server is ONLINE and listening on UDP port $BIND.${NC}"
        else
            echo -e "${RED}[FAILED] FRP KCP Server port $BIND is NOT responding locally.${NC}"
        fi
    else
        echo -e "${RED}Tunnel $ID is not configured on this server!${NC}"
    fi

    read -p "Press Enter to return..."
}

# ========== Manual Config Editor ==========
edit_config_manually() {
    show_logo
    echo -e "${CYAN}--- Edit KCP Tunnel Configuration File Manually ---${NC}"
    read -p "Enter Tunnel Index (1 to 10): " ID

    S_CONF="$CONFIG_DIR/frps_kcp_tunnel${ID}.toml"
    C_CONF="$CONFIG_DIR/frpc_kcp_tunnel${ID}.toml"
    CONF=""
    SVC=""

    if [ -f "$S_CONF" ]; then
        CONF="$S_CONF"
        SVC="frps_kcp_tunnel${ID}.service"
    elif [ -f "$C_CONF" ]; then
        CONF="$C_CONF"
        SVC="frpc_kcp_tunnel${ID}.service"
    else
        echo -e "${RED}Tunnel $ID configuration file does not exist!${NC}"
        sleep 2; return
    fi

    EDITOR_BIN=$(get_editor)
    echo -e "${YELLOW}Opening $CONF using $EDITOR_BIN...${NC}"
    sleep 1
    "$EDITOR_BIN" "$CONF"

    echo -e "${YELLOW}Restarting service $SVC to apply changes...${NC}"
    systemctl restart "$SVC"
    echo -e "${GREEN}Configuration updated and service restarted successfully!${NC}"
    read -p "Press Enter to return..."
}

# ========== Manage Actions ==========
manage_tunnels() {
    show_logo
    list_tunnels
    echo -e "${CYAN}1. Restart Tunnel${NC}"
    echo -e "${CYAN}2. Stop Tunnel${NC}"
    echo -e "${CYAN}3. View Logs${NC}"
    echo -e "${CYAN}4. Edit Config Manually (Nano/Vim)${NC}"
    echo -e "${LIGHT_RED}5. Delete Tunnel${NC}"
    echo -e "${CYAN}6. Set Auto-Restart Schedule (CronJob)${NC}"
    echo -e "${CYAN}0. Back${NC}"
    read -p "Select choice: " ACT
    
    if [ "$ACT" == "0" ]; then return; fi
    read -p "Enter Tunnel Index (1-10): " ID

    S_SVC="frps_kcp_tunnel${ID}.service"
    C_SVC="frpc_kcp_tunnel${ID}.service"
    SVC=""
    [ -f "/etc/systemd/system/$S_SVC" ] && SVC="$S_SVC"
    [ -f "/etc/systemd/system/$C_SVC" ] && SVC="$C_SVC"

    if [ -z "$SVC" ]; then
        echo -e "${RED}Tunnel $ID not found!${NC}"
        sleep 2; return
    fi

    case $ACT in
        1)
            systemctl restart "$SVC"
            echo -e "${GREEN}Tunnel $ID restarted.${NC}"
            ;;
        2)
            systemctl stop "$SVC"
            echo -e "${YELLOW}Tunnel $ID stopped.${NC}"
            ;;
        3)
            journalctl -u "$SVC" -n 50 --no-pager
            ;;
        4)
            edit_config_manually
            return
            ;;
        5)
            echo -e "${LIGHT_RED}WARNING: This will permanently delete the tunnel!${NC}"
            read -p "Type 'yes' to confirm deletion: " CONFIRM
            if [ "$CONFIRM" == "yes" ]; then
                systemctl disable --now "$SVC"
                rm -f "/etc/systemd/system/$SVC"
                rm -f "$CONFIG_DIR/frps_kcp_tunnel${ID}.toml" "$CONFIG_DIR/frpc_kcp_tunnel${ID}.toml"
                systemctl daemon-reload
                echo -e "${LIGHT_RED}Tunnel $ID deleted.${NC}"
            else
                echo -e "${YELLOW}Deletion cancelled.${NC}"
            fi
            ;;
        6)
            read -p "Enter restart interval in hours (e.g. 6 for every 6h): " HRS
            (crontab -l 2>/dev/null; echo "0 */$HRS * * * systemctl restart $SVC") | crontab -
            echo -e "${GREEN}Auto-restart schedule set for Tunnel $ID every $HRS hours.${NC}"
            ;;
    esac
    read -p "Press Enter to continue..."
}

# ========== Speedtest Module ==========
run_speedtest() {
    show_logo
    echo -e "${CYAN}--- Bandwidth SpeedTest Module (via KCP Tunnel) ---${NC}"
    read -p "Enter Tunnel Index for Speedtest (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-9]$|^10$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    DEFAULT_PORT=$((55209 + ID))

    echo -e "${YELLOW}Default iperf3 test port for Tunnel ${ID}: ${DEFAULT_PORT}${NC}\n"
    echo "1. Run iperf3 Server Mode (Run this on KHAREJ Server first)"
    echo "2. Run iperf3 Client Test (Run this on IRAN Server after server starts)"
    read -p "Select option: " TEST_OPT

    if [ "$TEST_OPT" == "1" ]; then
        allow_ufw_port "$DEFAULT_PORT"
        fuser -k "${DEFAULT_PORT}/tcp" >/dev/null 2>&1
        echo -e "${GREEN}Starting iperf3 server on port $DEFAULT_PORT... (Press CTRL+C to stop when test finishes)${NC}"
        iperf3 -s -p "$DEFAULT_PORT"

    elif [ "$TEST_OPT" == "2" ]; then
        read -p "Enter target port [Default: $DEFAULT_PORT]: " TARGET_PORT
        TARGET_PORT=${TARGET_PORT:-$DEFAULT_PORT}

        echo -e "\n${YELLOW}=== TRAFFIC USAGE ESTIMATION NOTICE ===${NC}"
        echo -e "Traffic usage depends on test duration and tunnel speed:"
        echo -e " - At 100 Mbps  : ~12.5 MB per second"
        echo -e " - At 500 Mbps  : ~62.5 MB per second"
        echo -e " - At 1000 Mbps : ~125.0 MB per second"
        echo -e "--------------------------------------------------"
        echo -e "1) 5 Seconds  (Low traffic usage)"
        echo -e "2) 10 Seconds (Standard test)"
        echo -e "3) Custom Duration"
        read -p "Select test duration [1-3]: " DUR_OPT

        case $DUR_OPT in
            1) DURATION=5 ;;
            2) DURATION=10 ;;
            3) 
                read -p "Enter custom duration in seconds: " DURATION
                DURATION=${DURATION:-10}
                ;;
            *) DURATION=10 ;;
        esac

        echo -e "\n${YELLOW}Testing through KCP FRP Tunnel...${NC}"
        echo -e "Target: 127.0.0.1:${TARGET_PORT}"
        echo -e "Running ${DURATION}-second TCP multi-stream test...\n"
        
        RAW_JSON=$(iperf3 -c 127.0.0.1 -p "$TARGET_PORT" -P 5 -t "$DURATION" --json 2>/dev/null)
        
        if [ -z "$RAW_JSON" ]; then
            echo -e "${RED}[ERROR] Speedtest failed! Could not connect to iperf3 server on port $TARGET_PORT.${NC}"
            echo -e "${YELLOW}Make sure Option 1 (Server Mode) is currently RUNNING on Kharej server!${NC}"
        else
            MBPS=$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    bps = data["end"]["sum_received"]["bits_per_second"]
    print(f"{bps / 1e6:.2f}")
except Exception:
    try:
        bps = data["end"]["sum_sent"]["bits_per_second"]
        print(f"{bps / 1e6:.2f}")
    except Exception:
        print("0")
' "$RAW_JSON" 2>/dev/null)

            if [ -n "$MBPS" ] && [ "$MBPS" != "0" ]; then
                RATING=0
                if (( $(echo "$MBPS > 500" | bc -l 2>/dev/null || echo 0) )); then RATING=10;
                elif (( $(echo "$MBPS > 300" | bc -l 2>/dev/null || echo 0) )); then RATING=9;
                elif (( $(echo "$MBPS > 150" | bc -l 2>/dev/null || echo 0) )); then RATING=8;
                elif (( $(echo "$MBPS > 80" | bc -l 2>/dev/null || echo 0) )); then RATING=7;
                elif (( $(echo "$MBPS > 40" | bc -l 2>/dev/null || echo 0) )); then RATING=5;
                else RATING=3; fi

                echo -e "\n${GREEN}================ SPEEDTEST RESULTS ================${NC}"
                echo -e "Tunnel ID       : ${ORANGE}${ID}${NC}"
                echo -e "Tunnel Port     : ${ORANGE}${TARGET_PORT}${NC}"
                echo -e "Throughput      : ${CYAN}${MBPS} Mbps${NC}"
                echo -e "Performance     : ${ORANGE}${RATING}/10${NC}"
                echo -e "${GREEN}===================================================${NC}\n"
            else
                echo -e "${RED}[ERROR] Failed to parse iperf3 test results.${NC}"
            fi
        fi
    fi
    read -p "Press Enter to return..."
}

# ========== Optimize System for KCP ==========
optimize_kcp_system() {
    show_logo
    echo -e "${CYAN}--- Optimize System for High-Performance KCP ---${NC}\n"
    
    cat << EOF > /etc/sysctl.d/99-frp-kcp.conf
# UDP Buffer Optimization for KCP/FRP
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.netdev_max_backlog = 5000
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.udp_mem = 8388608 12582912 16777216
EOF

    sysctl -p /etc/sysctl.d/99-frp-kcp.conf >/dev/null 2>&1
    echo -e "${GREEN}Kernel UDP buffers optimized and persisted in /etc/sysctl.d/99-frp-kcp.conf${NC}"
    echo -e "${YELLOW}Recommendation: Restart all KCP services or reboot the server for full effect.${NC}"
    read -p "Press Enter to return..."
}

# ========== Main Menu ==========
main_menu() {
    detect_location
    load_defaults
    while true; do
        show_logo
        echo -e "Server Location Status: ${YELLOW}[ ${SERVER_MODE} ]${NC}"
        echo -e "FRP Version: ${GREEN}v${FRP_VERSION}${NC} | Protocol: ${CYAN}KCP${NC}\n"
        
        list_tunnels

        echo -e "${CYAN}1. Install Dependencies & FRP v${FRP_VERSION}${NC}"
        echo -e "${ORANGE}2. Setup FRP KCP Server (Iran - Run on IRAN Server)${NC}"
        echo -e "${YELLOW}3. Setup FRP KCP Client (Kharej - Run on KHAREJ Server)${NC}"
        echo -e "${CYAN}4. Edit Tunnel Config Manually (Nano/Vim)${NC}"
        echo -e "${CYAN}5. Check Active Tunnel Health & Connection Status${NC}"
        echo -e "${CYAN}6. Manage / Restart / Logs / CronJobs / Delete Tunnels${NC}"
        echo -e "${CYAN}7. Run iperf3 Speedtest Mode${NC}"
        echo -e "${CYAN}8. Change Location Mode Manually (Toggle Iran/Kharej)${NC}"
        echo -e "${CYAN}9. Set Default Values for Setup (Pool, Token, Port Range)${NC}"
        echo -e "${CYAN}10. Optimize System for High KCP Bandwidth (UDP Buffers)${NC}"
        echo -e "${LIGHT_RED}0. Exit${NC}"
        echo "---------------------------------"
        read -p "Choose an option: " OPT

        case $OPT in
            1) install_dependencies_and_frp ;;
            2) setup_frps ;;
            3) setup_frpc ;;
            4) edit_config_manually ;;
            5) check_tunnel_health ;;
            6) manage_tunnels ;;
            7) run_speedtest ;;
            8) 
                if [ "$SERVER_MODE" == "IRAN" ]; then SERVER_MODE="KHAREJ"; else SERVER_MODE="IRAN"; fi
                ;;
            9) set_default_values ;;
            10) optimize_kcp_system ;;
            0) echo -e "${LIGHT_RED}Exiting...${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
