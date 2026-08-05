#!/bin/bash

# ==========================================
# Advanced FRP Tunnel Manager v1.0.0
# Optimized for TCP Tunneling & Multi-Port Forwarding
# ==========================================

VERSION="1.0.0"
FRP_VERSION="0.70.1"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script as root.${NC}"
  exit 1
fi

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

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
    echo -e "${YELLOW}           -- TCP Multi-Tunnel Manager v${VERSION} --${NC}\n"
}

# Location Auto Detection
detect_location() {
    if [ -z "$SERVER_MODE" ]; then
        COUNTRY_CODE=$(curl -s --max-time 3 https://ipapi.co/country/)
        if [ "$COUNTRY_CODE" == "IR" ]; then
            SERVER_MODE="IRAN"
        else
            SERVER_MODE="KHAREJ"
        fi
    fi
}

# UFW Whitelist helper
allow_ufw_port() {
    local port=$1
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            ufw allow "$port"/tcp >/dev/null 2>&1
            echo -e "${GREEN}[UFW] Port $port added to whitelist.${NC}"
        fi
    fi
}

# 1. Install Dependencies & FRP 0.70.1
install_dependencies_and_frp() {
    show_logo
    echo -e "${YELLOW}[1/3] Installing Dependencies (curl, wget, tar, iperf3, ufw, bc)...${NC}"
    apt-get update -y
    apt-get install -y curl wget tar iperf3 ufw bc cron

    echo -e "${YELLOW}[2/3] Downloading FRP v${FRP_VERSION}...${NC}"
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; return ;;
    esac

    TMP_DIR="/tmp/frp_install"
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
    read -p "Press Enter to return..."
}

# 2. Configure FRP Server (Iran)
setup_frps() {
    show_logo
    echo -e "${CYAN}--- Setup FRP Server (Iran / Inbound) ---${NC}"
    read -p "Enter Tunnel Index Number (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-10]$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    read -p "Enter Tunnel Name (e.g. nl1, de2): " TUNNEL_NAME
    read -p "Enter FRP Bind Port for Client [Default: $((7000 + ID))]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-$((7000 + ID))}
    
    read -p "Enter Authentication Token: " AUTH_TOKEN

    CONF_FILE="$CONFIG_DIR/frps_tunnel${ID}.toml"
    cat << EOF > "$CONF_FILE"
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
EOF

    # Service
    SERVICE_FILE="/etc/systemd/system/frps_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP Server Tunnel ${ID} (${TUNNEL_NAME})
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
    systemctl enable --now "frps_tunnel${ID}.service"
    allow_ufw_port "$BIND_PORT"

    echo -e "${GREEN}FRP Server Tunnel ${ID} (${TUNNEL_NAME}) successfully created and started on port ${BIND_PORT}!${NC}"
    read -p "Press Enter to return..."
}

# 3. Configure FRP Client (Kharej)
setup_frpc() {
    show_logo
    echo -e "${CYAN}--- Setup FRP Client (Kharej / Outbound) ---${NC}"
    read -p "Enter Tunnel Index Number (1 to 10): " ID
    if ! [[ "$ID" =~ ^[1-10]$ ]]; then
        echo -e "${RED}Invalid ID! Use 1 to 10.${NC}"
        sleep 2; return
    fi

    read -p "Enter Tunnel Name (e.g. nl1, de2): " TUNNEL_NAME
    read -p "Enter Iran Server IP or Domain: " IRAN_IP
    read -p "Enter FRP Server Bind Port [Default: $((7000 + ID))]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-$((7000 + ID))}
    read -p "Enter Authentication Token: " AUTH_TOKEN

    echo -e "${YELLOW}Enter local ports to forward separated by comma (e.g. 443,80,8443):${NC}"
    read -p "Ports: " PORTS_INPUT

    CONF_FILE="$CONFIG_DIR/frpc_tunnel${ID}.toml"
    cat << EOF > "$CONF_FILE"
serverAddr = "$IRAN_IP"
serverPort = $BIND_PORT
auth.method = "token"
auth.token = "$AUTH_TOKEN"
transport.tcpMux = true
transport.poolCount = 10

EOF

    IFS=',' read -ra ADDR <<< "$PORTS_INPUT"
    for PORT in "${ADDR[@]}"; do
        PORT=$(echo "$PORT" | xargs)
        cat << EOF >> "$CONF_FILE"
[[proxies]]
name = "${TUNNEL_NAME}_tcp_${PORT}"
type = "tcp"
localIP = "127.0.0.1"
localPort = $PORT
remotePort = $PORT

EOF
        allow_ufw_port "$PORT"
    done

    # Service
    SERVICE_FILE="/etc/systemd/system/frpc_tunnel${ID}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=FRP Client Tunnel ${ID} (${TUNNEL_NAME})
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
    systemctl enable --now "frpc_tunnel${ID}.service"

    echo -e "${GREEN}FRP Client Tunnel ${ID} (${TUNNEL_NAME}) created and started successfully!${NC}"
    read -p "Press Enter to return..."
}

# List Tunnels
list_tunnels() {
    echo -e "${PURPLE}--- Active Configured Tunnels ---${NC}"
    for i in {1..10}; do
        S_CONF="$CONFIG_DIR/frps_tunnel${i}.toml"
        C_CONF="$CONFIG_DIR/frpc_tunnel${i}.toml"
        
        if [ -f "$S_CONF" ]; then
            STATUS=$(systemctl is-active "frps_tunnel${i}.service" 2>/dev/null)
            if [ "$STATUS" == "active" ]; then
                ST_TXT="${GREEN}ONLINE${NC}"
            else
                ST_TXT="${RED}OFFLINE${NC}"
            fi
            echo -e "Tunnel $i (Server): Status [$ST_TXT] | Config: $S_CONF"
        elif [ -f "$C_CONF" ]; then
            STATUS=$(systemctl is-active "frpc_tunnel${i}.service" 2>/dev/null)
            if [ "$STATUS" == "active" ]; then
                ST_TXT="${GREEN}ONLINE${NC}"
            else
                ST_TXT="${RED}OFFLINE${NC}"
            fi
            echo -e "Tunnel $i (Client): Status [$ST_TXT] | Config: $C_CONF"
        else
            echo -e "Tunnel $i: ${YELLOW}Not Configured${NC}"
        fi
    done
    echo "---------------------------------"
}

# Manage Actions
manage_tunnels() {
    show_logo
    list_tunnels
    echo -e "${CYAN}1. Restart Tunnel${NC}"
    echo -e "${CYAN}2. Stop Tunnel${NC}"
    echo -e "${CYAN}3. View Logs${NC}"
    echo -e "${CYAN}4. Delete Tunnel${NC}"
    echo -e "${CYAN}5. Set Auto-Restart Schedule (CronJob)${NC}"
    echo -e "${CYAN}0. Back${NC}"
    read -p "Select choice: " ACT
    
    if [ "$ACT" == "0" ]; then return; fi
    read -p "Enter Tunnel Index (1-10): " ID

    S_SVC="frps_tunnel${ID}.service"
    C_SVC="frpc_tunnel${ID}.service"
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
            systemctl disable --now "$SVC"
            rm -f "/etc/systemd/system/$SVC"
            rm -f "$CONFIG_DIR/frps_tunnel${ID}.toml" "$CONFIG_DIR/frpc_tunnel${ID}.toml"
            systemctl daemon-reload
            echo -e "${RED}Tunnel $ID deleted.${NC}"
            ;;
        5)
            read -p "Enter restart interval in hours (e.g. 6 for every 6h): " HRS
            (crontab -l 2>/dev/null; echo "0 */$HRS * * * systemctl restart $SVC") | crontab -
            echo -e "${GREEN}Auto-restart schedule set for Tunnel $ID every $HRS hours.${NC}"
            ;;
    esac
    read -p "Press Enter to continue..."
}

# Speedtest Module (iperf3)
run_speedtest() {
    show_logo
    echo -e "${CYAN}--- Bandwidth SpeedTest Module ---${NC}"
    read -p "Enter Tunnel Index for Speedtest (1 to 10): " ID
    DEFAULT_PORT=$((55210 + ID))

    echo -e "${YELLOW}Default test port for Tunnel ${ID} is: ${DEFAULT_PORT}${NC}"
    echo "1. Run iperf3 Server Mode (Run this on Server first)"
    echo "2. Run iperf3 Client Test (Run this on Client after server starts)"
    read -p "Select option: " TEST_OPT

    if [ "$TEST_OPT" == "1" ]; then
        allow_ufw_port "$DEFAULT_PORT"
        echo -e "${GREEN}Starting iperf3 server on port $DEFAULT_PORT... (Press CTRL+C to stop when test finishes)${NC}"
        iperf3 -s -p "$DEFAULT_PORT"
    elif [ "$TEST_OPT" == "2" ]; then
        read -p "Enter Target IP/Domain (127.0.0.1 or Iran IP): " TARGET_IP
        echo -e "${YELLOW}Running 10-second multi-stream TCP test...${NC}"
        
        RESULT=$(iperf3 -c "$TARGET_IP" -p "$DEFAULT_PORT" -P 5 -t 10 --json 2>/dev/null)
        
        if [ -z "$RESULT" ]; then
            echo -e "${RED}Test failed! Make sure iperf3 server is running on the other side.${NC}"
        else
            SUM_BANDWIDTH=$(echo "$RESULT" | grep -o '"bits_per_second": [0-9.]*' | tail -n 1 | awk '{print $2}')
            MBPS=$(echo "scale=2; $SUM_BANDWIDTH / 1000000" | bc)
            
            echo -e "\n${GREEN}================ SPEEDTEST RESULTS ================${NC}"
            echo -e "Measured Throughput: ${CYAN}${MBPS} Mbits/sec${NC}"
            
            # Rating calculation
            RATING=0
            if (( $(echo "$MBPS > 500" | bc -l) )); then RATING=10;
            elif (( $(echo "$MBPS > 300" | bc -l) )); then RATING=9;
            elif (( $(echo "$MBPS > 150" | bc -l) )); then RATING=8;
            elif (( $(echo "$MBPS > 80" | bc -l) )); then RATING=7;
            elif (( $(echo "$MBPS > 40" | bc -l) )); then RATING=5;
            else RATING=3; fi

            echo -e "Performance Rating: ${YELLOW}${RATING} / 10${NC}"
            echo -e "${GREEN}===================================================${NC}\n"
        fi
    fi
    read -p "Press Enter to return..."
}

# Main Menu
main_menu() {
    detect_location
    while true; do
        show_logo
        echo -e "Server Location Status: ${YELLOW}[ ${SERVER_MODE} ]${NC}"
        echo -e "FRP Version: ${GREEN}v${FRP_VERSION}${NC}\n"
        
        list_tunnels

        echo -e "${CYAN}1. Install Dependencies & FRP v${FRP_VERSION}${NC}"
        echo -e "${CYAN}2. Setup FRP Server (Iran - Reverse Server)${NC}"
        echo -e "${CYAN}3. Setup FRP Client (Kharej - Reverse Client)${NC}"
        echo -e "${CYAN}4. Manage / Restart / Logs / CronJobs / Delete Tunnels${NC}"
        echo -e "${CYAN}5. Run iperf3 Speedtest Mode${NC}"
        echo -e "${CYAN}6. Change Location Mode Manually (Toggle Iran/Kharej)${NC}"
        echo -e "${RED}0. Exit${NC}"
        echo "---------------------------------"
        read -p "Choose an option: " OPT

        case $OPT in
            1) install_dependencies_and_frp ;;
            2) setup_frps ;;
            3) setup_frpc ;;
            4) manage_tunnels ;;
            5) run_speedtest ;;
            6) 
                if [ "$SERVER_MODE" == "IRAN" ]; then SERVER_MODE="KHAREJ"; else SERVER_MODE="IRAN"; fi
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
