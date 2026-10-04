#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
#  ELITE-X SLOWDNS SCRIPT v3.6 - FALCON ULTRA C + SERVER MESSAGE
# ╚══════════════════════════════════════════════════════════════╝

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
PURPLE='\033[0;35m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; BOLD='\033[1m'
ORANGE='\033[0;33m'; LIGHT_RED='\033[1;31m'; LIGHT_GREEN='\033[1;32m'; GRAY='\033[0;90m'
NC='\033[0m'

STATIC_PRIVATE_KEY="7f207e92ab7cb365aad1966b62d2cfbd3f450fe8e523a38ffc7ecfbcec315693"
STATIC_PUBLIC_KEY="40aa057fcb2574e1e9223ea46457f9fdf9d60a2a1c23da87602202d93b41aa04"
ACTIVATION_KEY="ELITE"
TIMEZONE="Africa/Dar_es_Salaam"

USER_DB="/etc/elite-x/users"
USAGE_DB="/etc/elite-x/data_usage"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
PIDTRACK_DIR="$BANDWIDTH_DIR/pidtrack"
BANNED_DB="/etc/elite-x/banned"
CONN_DB="/etc/elite-x/connections"
DELETED_DB="/etc/elite-x/deleted"
AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
SERVER_MSG_DIR="/etc/elite-x/server_msg"
USER_MSG_DIR="/etc/elite-x/user_messages"

show_banner() {
    clear
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD} ELITE-X SLOWDNS v3.6 - FALCON   ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_color() { echo -e "${2}${1}${NC}"; }
set_timezone() { timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true; }

# ═══════════════════════════════════════════════════════════
# FORCE USER MESSAGE ON SSH LOGIN (FIXED)
# ═══════════════════════════════════════════════════════════
force_user_message() {
    local username="$1"
    local msg_file="$USER_MSG_DIR/$username"
    
    mkdir -p "$USER_MSG_DIR"
    
    # Generate user-specific message with real-time data
    cat > "$msg_file" <<EOF
╔═══════════════════════════════════╗
║       v3.6 FALCON  USER INFO      ║
╠═══════════════════════════════════╣
║  USERNAME   : $username
╚═══════════════════════════════════╝
EOF

    # Append live data
    local expire_date=$(grep "Expire:" "$USER_DB/$username" | awk '{print $2}')
    local bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$username" | awk '{print $2}')
    local conn_limit=$(grep "Conn_Limit:" "$USER_DB/$username" | awk '{print $2}')
    
    bandwidth_gb=${bandwidth_gb:-0}
    conn_limit=${conn_limit:-1}
    
    local usage_bytes=$(cat "$BANDWIDTH_DIR/${username}.usage" 2>/dev/null || echo 0)
    local usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")
    
    local current_conn=0
    current_conn=$(who | grep -wc "$username" 2>/dev/null || echo 0)
    [ "$current_conn" -eq 0 ] && current_conn=$(ps aux 2>/dev/null | grep "sshd:" | grep "$username" | grep -v grep | grep -v "sshd:.*@notty" | wc -l)
    current_conn=${current_conn:-0}
    
    local now_ts=$(date +%s)
    local expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
    local remaining_seconds=$((expire_ts - now_ts))
    local remaining_days=$((remaining_seconds / 86400))
    local remaining_hours=$(((remaining_seconds % 86400) / 3600))
    
    [ $remaining_days -lt 0 ] && remaining_days=0
    [ $remaining_hours -lt 0 ] && remaining_hours=0
    
    local bw_display="Unlimited"
    [ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"
    
    local status="🟢 ACTIVE"
    if [ $remaining_days -le 0 ]; then
        status="⛔ EXPIRED"
    elif [ $remaining_days -le 3 ]; then
        status="⚠️ EXPIRING SOON"
    fi
    
    cat >> "$msg_file" <<EOF
══════════════════════════════

EXPIRE    : $expire_date
─────────────────────────────

REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────

LIMIT GB  : $bw_display
─────────────────────────────

USAGE GB  : ${usage_gb} GB
─────────────────────────────
CONNECTION : ${current_conn}/${conn_limit}
─────────────────────────────

STATUS : $status
══════════════════════════════
     Thanks for using ELITE-X services
══════════════════════════════
EOF

    chmod 644 "$msg_file"
    echo "$msg_file"
}

# ═══════════════════════════════════════════════════════════
# SSH CONFIGURATION WITH USER-SPECIFIC BANNERS (FIXED)
# ═══════════════════════════════════════════════════════════
configure_ssh_for_vpn() {
    echo -e "${YELLOW}🔧 Configuring SSH for VPN + User Messages...${NC}"
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    
    # Remove old directives
    sed -i '/^Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/^Match User/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    
    # Base config
    cat > /etc/ssh/sshd_config.d/elite-x-base.conf <<'SSHCONF'
# ELITE-X VPN Base Configuration
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes

AllowTcpForwarding yes
AllowAgentForwarding yes
GatewayPorts yes
PermitTunnel yes
PermitOpen any

TCPKeepAlive yes
ClientAliveInterval 60
ClientAliveCountMax 3
MaxStartups 100:30:200
MaxSessions 100

UseDNS no
LogLevel VERBOSE
SSHCONF

    # Create dynamic user banner config
    cat > /etc/ssh/sshd_config.d/elite-x-users.conf <<'SSHCONF2'
# ELITE-X Dynamic User Banners - Managed by system
SSHCONF2

    # Add all existing users
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            [ -f "$user_file" ] || continue
            local username=$(basename "$user_file")
            local msg_file=$(force_user_message "$username")
            echo "Match User $username" >> /etc/ssh/sshd_config.d/elite-x-users.conf
            echo "    Banner $msg_file" >> /etc/ssh/sshd_config.d/elite-x-users.conf
        done
    fi
    
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    
    echo -e "${GREEN}✅ SSH configured with User Messages${NC}"
}

# ═══════════════════════════════════════════════════════════
# PAM + LOGIN SCRIPT - AUTO UPDATE USER MESSAGE ON LOGIN
# ═══════════════════════════════════════════════════════════
configure_pam_user_message() {
    echo -e "${YELLOW}🔧 Configuring PAM for automatic user message update...${NC}"
    
    # Create login script that updates user message before showing
    cat > /usr/local/bin/elite-x-update-user-msg <<'SCRIPT'
#!/bin/bash
USERNAME="$PAM_USER"
if [ -n "$USERNAME" ] && [ -f "/etc/elite-x/users/$USERNAME" ]; then
    # Force update user message before login
    /usr/local/bin/elite-x-force-user-message "$USERNAME" 2>/dev/null
fi
SCRIPT
    chmod +x /usr/local/bin/elite-x-update-user-msg
    
    # Create forced message updater
    cat > /usr/local/bin/elite-x-force-user-message <<'FORCE'
#!/bin/bash
USERNAME="$1"
USER_DB="/etc/elite-x/users"
BANDWIDTH_DIR="/etc/elite-x/bandwidth"
USER_MSG_DIR="/etc/elite-x/user_messages"

if [ -z "$USERNAME" ] || [ ! -f "$USER_DB/$USERNAME" ]; then
    exit 0
fi

mkdir -p "$USER_MSG_DIR"
MSG_FILE="$USER_MSG_DIR/$USERNAME"

# Generate fresh message
expire_date=$(grep "Expire:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=$(grep "Bandwidth_GB:" "$USER_DB/$USERNAME" | awk '{print $2}')
conn_limit=$(grep "Conn_Limit:" "$USER_DB/$USERNAME" | awk '{print $2}')
bandwidth_gb=${bandwidth_gb:-0}
conn_limit=${conn_limit:-1}

usage_bytes=$(cat "$BANDWIDTH_DIR/${USERNAME}.usage" 2>/dev/null || echo 0)
usage_gb=$(echo "scale=2; $usage_bytes / 1073741824" | bc 2>/dev/null || echo "0.00")

current_conn=0
current_conn=$(who | grep -wc "$USERNAME" 2>/dev/null || echo 0)
[ "$current_conn" -eq 0 ] && current_conn=$(ps aux 2>/dev/null | grep "sshd:" | grep "$USERNAME" | grep -v grep | grep -v "sshd:.*@notty" | wc -l)
current_conn=${current_conn:-0}

now_ts=$(date +%s)
expire_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
remaining_seconds=$((expire_ts - now_ts))
remaining_days=$((remaining_seconds / 86400))
remaining_hours=$(((remaining_seconds % 86400) / 3600))
[ $remaining_days -lt 0 ] && remaining_days=0
[ $remaining_hours -lt 0 ] && remaining_hours=0

bw_display="Unlimited"
[ "$bandwidth_gb" != "0" ] && bw_display="${bandwidth_gb} GB"

status="🟢 ACTIVE"
if [ $remaining_days -le 0 ]; then
    status="⛔ EXPIRED"
elif [ $remaining_days -le 3 ]; then
    status="⚠️ EXPIRING SOON"
fi

cat > "$MSG_FILE" <<EOF
═════════════════════════════

ELITE-X SLOWDNS VPN  
═════════════════════════════

 USERNAME: $USERNAME
─────────────────────────────

 EXPIRE  : $expire_date
─────────────────────────────

 REMAINING : ${remaining_days} day(s) + ${remaining_hours} hr(s)
─────────────────────────────

LIMIT GB: $bw_display
USAGE GB: ${usage_gb} GB
─────────────────────────────

CONNECTION: ${current_conn}/${conn_limit}
─────────────────────────────

STATUS   : $status
═════════════════════════════

Thanks for using ELITE-X services 
═════════════════════════════
EOF

chmod 644 "$MSG_FILE"

# Update SSH config for this user
sed -i "/Match User $USERNAME/,/Banner/d" /etc/ssh/sshd_config.d/elite-x-users.conf 2>/dev/null
echo "Match User $USERNAME" >> /etc/ssh/sshd_config.d/elite-x-users.conf
echo "    Banner $MSG_FILE" >> /etc/ssh/sshd_config.d/elite-x-users.conf

# Reload SSH without killing active connections
systemctl reload sshd 2>/dev/null || kill -HUP $(cat /var/run/sshd.pid 2>/dev/null) 2>/dev/null || true

echo "$USERNAME: message updated" >> /var/log/elite-x-user-msgs.log 2>/dev/null
FORCE
    chmod +x /usr/local/bin/elite-x-force-user-message
    
    # Remove old PAM entries
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    
    # Add PAM session hook
    echo "session optional pam_exec.so seteuid /usr/local/bin/elite-x-update-user-msg" >> /etc/pam.d/sshd
    
    echo -e "${GREEN}✅ PAM configured - user message updates on each login${NC}"
}

# ═══════════════════════════════════════════════════════════
# SYSTEM OPTIMIZATION FOR VPN
# ═══════════════════════════════════════════════════════════
optimize_system_for_vpn() {
    echo -e "${YELLOW}🔧 Optimizing system for VPN connections...${NC}"
    
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.ip_no_pmtu_disc=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.route.flush=1 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_default=262144 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_default=262144 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_mem='65536 131072 262144' >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_rmem_min=16384 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_wmem_min=16384 >/dev/null 2>&1 || true
    
    cat > /etc/sysctl.d/99-elite-x-vpn.conf <<SYSCTL
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.tcp_mtu_probing=1
net.ipv4.ip_no_pmtu_disc=0
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.core.rmem_default=262144
net.core.wmem_default=262144
net.ipv4.udp_mem=65536 131072 262144
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
SYSCTL
    sysctl -p /etc/sysctl.d/99-elite-x-vpn.conf >/dev/null 2>&1 || true
    
    iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true
    iptables -A FORWARD -i lo -j ACCEPT 2>/dev/null || true
    iptables -A FORWARD -o lo -j ACCEPT 2>/dev/null || true
    sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1 || true
    
    echo -e "${GREEN}✅ System optimized for VPN${NC}"
}

# ═══════════════════════════════════════════════════════════
# C-BASED EDNS PROXY (FIXED)
# ═══════════════════════════════════════════════════════════
create_c_edns_proxy() {
    echo -e "${YELLOW}📝 Compiling C-based EDNS Proxy (Fixed)...${NC}"
    
    cat > /tmp/edns_proxy.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <pthread.h>

#define BUFFER_SIZE 4096
#define DNS_PORT 53
#define BACKEND_PORT 5300
#define MAX_EDNS_SIZE 1800
#define MIN_EDNS_SIZE 512
#define MAX_THREADS 200

static volatile int running = 1;

void signal_handler(int sig) { running = 0; }

int skip_name(const unsigned char *data, int offset, int max_len) {
    while (offset < max_len) {
        unsigned char len = data[offset]; offset++;
        if (len == 0) break;
        if ((len & 0xC0) == 0xC0) { offset++; break; }
        offset += len;
    }
    return offset;
}

void modify_edns(unsigned char *data, int *len, unsigned short max_size) {
    if (*len < 12) return;
    int offset = 12;
    unsigned short qdcount, ancount, nscount, arcount;
    memcpy(&qdcount, data + 4, 2); qdcount = ntohs(qdcount);
    memcpy(&ancount, data + 6, 2); ancount = ntohs(ancount);
    memcpy(&nscount, data + 8, 2); nscount = ntohs(nscount);
    memcpy(&arcount, data + 10, 2); arcount = ntohs(arcount);
    
    int i;
    for (i = 0; i < qdcount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 4 > *len) return;
        offset += 4;
    }
    for (i = 0; i < ancount + nscount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 10 > *len) return;
        unsigned short rdlength;
        memcpy(&rdlength, data + offset + 8, 2);
        rdlength = ntohs(rdlength);
        offset += 10 + rdlength;
    }
    for (i = 0; i < arcount; i++) {
        offset = skip_name(data, offset, *len);
        if (offset + 10 > *len) return;
        unsigned short rrtype;
        memcpy(&rrtype, data + offset, 2);
        rrtype = ntohs(rrtype);
        if (rrtype == 41) {
            unsigned short size = htons(max_size);
            memcpy(data + offset + 2, &size, 2);
            return;
        }
        unsigned short rdlength;
        memcpy(&rdlength, data + offset + 8, 2);
        rdlength = ntohs(rdlength);
        offset += 10 + rdlength;
    }
}

typedef struct {
    int sock;
    struct sockaddr_in client_addr;
    socklen_t client_len;
    unsigned char *data;
    int data_len;
} proxy_thread_args_t;

void *handle_proxy(void *arg) {
    proxy_thread_args_t *args = (proxy_thread_args_t *)arg;
    int backend_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (backend_sock < 0) { free(args->data); free(args); return NULL; }
    
    struct timeval btv;
    btv.tv_sec = 5; btv.tv_usec = 0;
    setsockopt(backend_sock, SOL_SOCKET, SO_RCVTIMEO, &btv, sizeof(btv));
    
    struct sockaddr_in backend_addr;
    memset(&backend_addr, 0, sizeof(backend_addr));
    backend_addr.sin_family = AF_INET;
    backend_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    backend_addr.sin_port = htons(BACKEND_PORT);
    
    unsigned char response[BUFFER_SIZE];
    int len = args->data_len;
    modify_edns(args->data, &len, MAX_EDNS_SIZE);
    
    sendto(backend_sock, args->data, len, 0, (struct sockaddr*)&backend_addr, sizeof(backend_addr));
    
    socklen_t back_len = sizeof(backend_addr);
    int rn = recvfrom(backend_sock, response, BUFFER_SIZE, 0, (struct sockaddr*)&backend_addr, &back_len);
    
    if (rn > 0) {
        len = rn;
        modify_edns(response, &len, MIN_EDNS_SIZE);
        sendto(args->sock, response, len, 0, (struct sockaddr*)&args->client_addr, args->client_len);
    }
    
    close(backend_sock);
    free(args->data);
    free(args);
    return NULL;
}

int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { perror("socket creation failed"); return 1; }
    
    int reuse = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    int rcvbuf = 262144, sndbuf = 262144;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
    setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(DNS_PORT);
    
    system("fuser -k 53/udp 2>/dev/null");
    usleep(1000000);
    
    if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        system("fuser -k 53/udp 2>/dev/null");
        usleep(2000000);
        if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            perror("bind failed"); close(sock); return 1;
        }
    }
    
    struct timeval tv;
    tv.tv_sec = 1; tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    
    fprintf(stderr, "C-EDNS Proxy running on port 53 (fixed version)\n");
    
    while (running) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        unsigned char *buffer = malloc(BUFFER_SIZE);
        if (!buffer) { usleep(10000); continue; }
        
        int n = recvfrom(sock, buffer, BUFFER_SIZE, 0, (struct sockaddr*)&client_addr, &client_len);
        if (n < 0) { free(buffer); if (errno == EAGAIN || errno == EWOULDBLOCK) continue; if (!running) break; usleep(10000); continue; }
        
        proxy_thread_args_t *args = malloc(sizeof(proxy_thread_args_t));
        if (!args) { free(buffer); continue; }
        
        args->sock = sock;
        args->client_addr = client_addr;
        args->client_len = client_len;
        args->data = buffer;
        args->data_len = n;
        
        pthread_t thread;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        pthread_create(&thread, &attr, handle_proxy, args);
        pthread_attr_destroy(&attr);
    }
    
    close(sock);
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -pthread -o /usr/local/bin/elite-x-edns-proxy /tmp/edns_proxy.c 2>/dev/null
    rm -f /tmp/edns_proxy.c
    
    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        chmod +x /usr/local/bin/elite-x-edns-proxy
        echo -e "${GREEN}✅ C EDNS Proxy compiled successfully${NC}"
        return 0
    else
        echo -e "${RED}❌ C EDNS Proxy compilation failed${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED BANDWIDTH MONITOR (ENHANCED)
# ═══════════════════════════════════════════════════════════
create_c_bandwidth_monitor() {
    echo -e "${YELLOW}📝 Compiling C Bandwidth Monitor...${NC}"
    
    cat > /tmp/bw_monitor.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <signal.h>
#include <pwd.h>
#include <ctype.h>

#define USER_DB "/etc/elite-x/users"
#define BW_DIR "/etc/elite-x/bandwidth"
#define PID_DIR "/etc/elite-x/bandwidth/pidtrack"
#define BANNED_DIR "/etc/elite-x/banned"
#define SCAN_INTERVAL 30
#define GB_BYTES 1073741824.0

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

long long get_process_io(int pid) {
    char path[256];
    snprintf(path, sizeof(path), "/proc/%d/io", pid);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    long long rchar = 0, wchar = 0;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "rchar:", 6) == 0) sscanf(line + 7, "%lld", &rchar);
        else if (strncmp(line, "wchar:", 6) == 0) sscanf(line + 7, "%lld", &wchar);
    }
    fclose(f);
    return rchar + wchar;
}

int is_numeric(const char *str) { for (; *str; str++) if (!isdigit(*str)) return 0; return 1; }

int get_sshd_pids(const char *username, int *pids, int max_pids) {
    int count = 0;
    DIR *proc = opendir("/proc");
    if (!proc) return 0;
    struct dirent *entry;
    while ((entry = readdir(proc)) && count < max_pids) {
        if (!is_numeric(entry->d_name)) continue;
        int pid = atoi(entry->d_name);
        char comm_path[256];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[256] = {0};
        fgets(comm, sizeof(comm), f);
        fclose(f);
        comm[strcspn(comm, "\n")] = 0;
        if (strcmp(comm, "sshd") == 0) {
            char status_path[256];
            snprintf(status_path, sizeof(status_path), "/proc/%d/status", pid);
            FILE *sf = fopen(status_path, "r");
            if (!sf) continue;
            char line[256], uid_str[32] = {0};
            while (fgets(line, sizeof(line), sf)) {
                if (strncmp(line, "Uid:", 4) == 0) { sscanf(line, "%*s %s", uid_str); break; }
            }
            fclose(sf);
            int uid = atoi(uid_str);
            struct passwd *pw = getpwuid(uid);
            if (pw && strcmp(pw->pw_name, username) == 0) {
                char stat_path[256];
                snprintf(stat_path, sizeof(stat_path), "/proc/%d/stat", pid);
                FILE *stf = fopen(stat_path, "r");
                if (stf) {
                    int ppid;
                    char stat_buf[1024];
                    fgets(stat_buf, sizeof(stat_buf), stf);
                    sscanf(stat_buf, "%*d %*s %*c %d", &ppid);
                    fclose(stf);
                    if (ppid != 1) pids[count++] = pid;
                }
            }
        }
    }
    closedir(proc);
    return count;
}

int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(BW_DIR, 0755); mkdir(PID_DIR, 0755); mkdir(BANNED_DIR, 0755);
    
    while (running) {
        DIR *user_dir = opendir(USER_DB);
        if (!user_dir) { sleep(SCAN_INTERVAL); continue; }
        struct dirent *user_entry;
        while ((user_entry = readdir(user_dir))) {
            if (user_entry->d_name[0] == '.') continue;
            char user_file[512];
            snprintf(user_file, sizeof(user_file), "%s/%s", USER_DB, user_entry->d_name);
            FILE *uf = fopen(user_file, "r");
            if (!uf) continue;
            double bandwidth_gb = 0;
            char line[256];
            while (fgets(line, sizeof(line), uf)) {
                if (strncmp(line, "Bandwidth_GB:", 13) == 0) sscanf(line + 13, "%lf", &bandwidth_gb);
            }
            fclose(uf);
            if (bandwidth_gb <= 0) continue;
            
            int pids[100];
            int pid_count = get_sshd_pids(user_entry->d_name, pids, 100);
            if (pid_count == 0) {
                char cmd[512];
                snprintf(cmd, sizeof(cmd), "rm -f %s/%s__*.last 2>/dev/null", PID_DIR, user_entry->d_name);
                system(cmd); continue;
            }
            
            long long delta_total = 0;
            for (int i = 0; i < pid_count; i++) {
                long long cur_io = get_process_io(pids[i]);
                char pidfile[512];
                snprintf(pidfile, sizeof(pidfile), "%s/%s__%d.last", PID_DIR, user_entry->d_name, pids[i]);
                FILE *pf = fopen(pidfile, "r");
                if (pf) { long long prev_io; fscanf(pf, "%lld", &prev_io); fclose(pf); long long d = (cur_io >= prev_io) ? (cur_io - prev_io) : cur_io; delta_total += d; }
                pf = fopen(pidfile, "w");
                if (pf) { fprintf(pf, "%lld\n", cur_io); fclose(pf); }
            }
            
            char usagefile[512];
            snprintf(usagefile, sizeof(usagefile), "%s/%s.usage", BW_DIR, user_entry->d_name);
            long long accumulated = 0;
            FILE *accf = fopen(usagefile, "r");
            if (accf) { fscanf(accf, "%lld", &accumulated); fclose(accf); }
            long long new_total = accumulated + delta_total;
            accf = fopen(usagefile, "w");
            if (accf) { fprintf(accf, "%lld\n", new_total); fclose(accf); }
            
            long long quota_bytes = (long long)(bandwidth_gb * GB_BYTES);
            if (new_total >= quota_bytes) {
                char cmd[1024];
                snprintf(cmd, sizeof(cmd), "passwd -S %s 2>/dev/null | grep -q 'L' || (usermod -L %s 2>/dev/null && killall -u %s -9 2>/dev/null && echo '%s - BLOCKED: Bandwidth quota exceeded %.1fGB' >> %s/%s)", user_entry->d_name, user_entry->d_name, user_entry->d_name, "BLOCKED", bandwidth_gb, BANNED_DIR, user_entry->d_name);
                system(cmd);
            }
        }
        closedir(user_dir);
        sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-bandwidth-c /tmp/bw_monitor.c 2>/dev/null
    rm -f /tmp/bw_monitor.c
    
    if [ -f /usr/local/bin/elite-x-bandwidth-c ]; then
        chmod +x /usr/local/bin/elite-x-bandwidth-c
        cat > /etc/systemd/system/elite-x-bandwidth.service <<EOF
[Unit]
Description=ELITE-X C Bandwidth Monitor (GB Limits)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-bandwidth-c
Restart=always
RestartSec=10
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Bandwidth Monitor compiled${NC}"
    else
        echo -e "${RED}❌ C Bandwidth Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED CONNECTION MONITOR
# ═══════════════════════════════════════════════════════════
create_c_connection_monitor() {
    echo -e "${YELLOW}📝 Compiling C Connection Monitor...${NC}"
    
    cat > /tmp/conn_monitor.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
#include <pwd.h>
#include <ctype.h>
#include <sys/stat.h>

#define USER_DB "/etc/elite-x/users"
#define CONN_DB "/etc/elite-x/connections"
#define BANNED_DIR "/etc/elite-x/banned"
#define DELETED_DIR "/etc/elite-x/deleted"
#define BW_DIR "/etc/elite-x/bandwidth"
#define PID_DIR "/etc/elite-x/bandwidth/pidtrack"
#define AUTOBAN_FLAG "/etc/elite-x/autoban_enabled"
#define SCAN_INTERVAL 5

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

int is_numeric(const char *str) { for (; *str; str++) if (!isdigit(*str)) return 0; return 1; }

int get_connection_count(const char *username) {
    int count = 0;
    DIR *proc = opendir("/proc");
    if (!proc) return 0;
    struct dirent *entry;
    while ((entry = readdir(proc))) {
        if (!is_numeric(entry->d_name)) continue;
        int pid = atoi(entry->d_name);
        char comm_path[256];
        snprintf(comm_path, sizeof(comm_path), "/proc/%d/comm", pid);
        FILE *f = fopen(comm_path, "r");
        if (!f) continue;
        char comm[256] = {0};
        fgets(comm, sizeof(comm), f);
        fclose(f);
        comm[strcspn(comm, "\n")] = 0;
        if (strcmp(comm, "sshd") == 0) {
            char status_path[256];
            snprintf(status_path, sizeof(status_path), "/proc/%d/status", pid);
            FILE *sf = fopen(status_path, "r");
            if (!sf) continue;
            char line[256], uid_str[32] = {0};
            while (fgets(line, sizeof(line), sf)) {
                if (strncmp(line, "Uid:", 4) == 0) { sscanf(line, "%*s %s", uid_str); break; }
            }
            fclose(sf);
            int uid = atoi(uid_str);
            struct passwd *pw = getpwuid(uid);
            if (pw && strcmp(pw->pw_name, username) == 0) {
                char stat_path[256];
                snprintf(stat_path, sizeof(stat_path), "/proc/%d/stat", pid);
                FILE *stf = fopen(stat_path, "r");
                if (stf) {
                    int ppid;
                    char stat_buf[1024];
                    fgets(stat_buf, sizeof(stat_buf), stf);
                    sscanf(stat_buf, "%*d %*s %*c %d", &ppid);
                    fclose(stf);
                    if (ppid != 1) count++;
                }
            }
        }
    }
    closedir(proc);
    return count;
}

void delete_expired_user(const char *username, const char *reason) {
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "cp %s/%s %s/%s_$(date +%%Y%%m%%d_%%H%%M%%S) 2>/dev/null; pkill -u %s 2>/dev/null; killall -u %s -9 2>/dev/null; userdel -r %s 2>/dev/null; rm -f %s/%s %s/%s %s/%s %s/%s %s/%s.usage; rm -f %s/%s__*.last 2>/dev/null; logger -t 'elite-x' 'Auto-deleted user: %s (%s)'", USER_DB, username, DELETED_DIR, username, username, username, username, USER_DB, username, "/etc/elite-x/data_usage", username, CONN_DB, username, BANNED_DIR, username, BW_DIR, username, PID_DIR, username, username, reason);
    system(cmd);
}

int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    mkdir(CONN_DB, 0755); mkdir(BANNED_DIR, 0755); mkdir(DELETED_DIR, 0755); mkdir(BW_DIR, 0755); mkdir(PID_DIR, 0755);
    
    while (running) {
        time_t current_ts = time(NULL);
        DIR *user_dir = opendir(USER_DB);
        if (!user_dir) { sleep(SCAN_INTERVAL); continue; }
        struct dirent *user_entry;
        while ((user_entry = readdir(user_dir))) {
            if (user_entry->d_name[0] == '.') continue;
            struct passwd *pw = getpwnam(user_entry->d_name);
            if (!pw) { char rm_cmd[512]; snprintf(rm_cmd, sizeof(rm_cmd), "rm -f %s/%s", USER_DB, user_entry->d_name); system(rm_cmd); continue; }
            
            char user_file[512];
            snprintf(user_file, sizeof(user_file), "%s/%s", USER_DB, user_entry->d_name);
            FILE *uf = fopen(user_file, "r");
            if (!uf) continue;
            char expire_date[32] = {0};
            int conn_limit = 1;
            char line[256];
            while (fgets(line, sizeof(line), uf)) {
                if (strncmp(line, "Expire:", 7) == 0) sscanf(line + 8, "%s", expire_date);
                else if (strncmp(line, "Conn_Limit:", 11) == 0) sscanf(line + 12, "%d", &conn_limit);
            }
            fclose(uf);
            
            if (strlen(expire_date) > 0) {
                struct tm tm = {0};
                if (strptime(expire_date, "%Y-%m-%d", &tm)) {
                    time_t expire_ts = mktime(&tm);
                    if (current_ts > expire_ts) {
                        char reason[256];
                        snprintf(reason, sizeof(reason), "Account expired on %s", expire_date);
                        delete_expired_user(user_entry->d_name, reason);
                        continue;
                    }
                }
            }
            
            int current_conn = get_connection_count(user_entry->d_name);
            char conn_file[512];
            snprintf(conn_file, sizeof(conn_file), "%s/%s", CONN_DB, user_entry->d_name);
            FILE *cf = fopen(conn_file, "w");
            if (cf) { fprintf(cf, "%d\n", current_conn); fclose(cf); }
            
            FILE *abf = fopen(AUTOBAN_FLAG, "r");
            int autoban = 0;
            if (abf) { fscanf(abf, "%d", &autoban); fclose(abf); }
            
            if (current_conn > conn_limit && autoban == 1) {
                char lock_cmd[1024];
                snprintf(lock_cmd, sizeof(lock_cmd), "passwd -S %s 2>/dev/null | grep -q 'L' || (usermod -L %s 2>/dev/null && pkill -u %s 2>/dev/null && echo '%s - BLOCKED: Exceeded connection limit %d/%d' >> %s/%s)", user_entry->d_name, user_entry->d_name, user_entry->d_name, "BLOCKED", current_conn, conn_limit, BANNED_DIR, user_entry->d_name);
                system(lock_cmd);
            }
        }
        closedir(user_dir);
        sleep(SCAN_INTERVAL);
    }
    return 0;
}
CEOF

    gcc -O3 -march=native -mtune=native -flto -o /usr/local/bin/elite-x-connmon-c /tmp/conn_monitor.c 2>/dev/null
    rm -f /tmp/conn_monitor.c
    
    if [ -f /usr/local/bin/elite-x-connmon-c ]; then
        chmod +x /usr/local/bin/elite-x-connmon-c
        cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=ELITE-X C Connection Monitor (Auto-Ban + Auto-Delete)
After=network.target ssh.service
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-connmon-c
Restart=always
RestartSec=5
CPUQuota=20%
MemoryMax=50M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Connection Monitor compiled${NC}"
    else
        echo -e "${RED}❌ C Connection Monitor compilation failed${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED NETWORK BOOSTER
# ═══════════════════════════════════════════════════════════
create_c_network_booster() {
    echo -e "${YELLOW}📝 Compiling C Network Booster...${NC}"
    
    cat > /tmp/net_booster.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>

static volatile int running = 1;
void signal_handler(int sig) { running = 0; }

void apply_tcp_optimizations() {
    system("sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1");
    system("sysctl -w net.core.rmem_default=262144 >/dev/null 2>&1");
    system("sysctl -w net.core.wmem_default=262144 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_rmem='4096 87380 134217728' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_wmem='4096 65536 134217728' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_syn_backlog=8192 >/dev/null 2>&1");
    system("sysctl -w net.core.somaxconn=8192 >/dev/null 2>&1");
    system("sysctl -w net.core.netdev_max_backlog=5000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_max_tw_buckets=2000000 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_fin_timeout=10 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_time=60 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_intvl=10 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.tcp_keepalive_probes=6 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_mem='65536 131072 262144' >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_rmem_min=16384 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.udp_wmem_min=16384 >/dev/null 2>&1");
    system("sysctl -w net.core.optmem_max=65536 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1");
    system("sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1");
    fprintf(stderr, "C Network Booster: TCP/UDP/VPN optimizations applied\n");
}

int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    apply_tcp_optimizations();
    while (running) { sleep(3600); if (running) apply_tcp_optimizations(); }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-netbooster /tmp/net_booster.c 2>/dev/null
    rm -f /tmp/net_booster.c
    
    if [ -f /usr/local/bin/elite-x-netbooster ]; then
        chmod +x /usr/local/bin/elite-x-netbooster
        cat > /etc/systemd/system/elite-x-netbooster.service <<EOF
[Unit]
Description=ELITE-X C Network Booster (TCP Optimizer)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-netbooster
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Network Booster compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED DNS CACHE OPTIMIZER
# ═══════════════════════════════════════════════════════════
create_c_dns_cache() {
    echo -e "${YELLOW}📝 Compiling C DNS Cache Optimizer...${NC}"
    
    cat > /tmp/dns_cache.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
void flush_dns_cache() {
    system("systemctl restart systemd-resolved 2>/dev/null || true");
    system("resolvectl flush-caches 2>/dev/null || true");
    system("killall -HUP dnsmasq 2>/dev/null || true");
    fprintf(stderr, "C DNS Cache: Flushed\n");
}
void optimize_resolv_conf() {
    FILE *f = fopen("/etc/resolv.conf", "w");
    if (f) { fprintf(f, "nameserver 8.8.8.8\nnameserver 8.8.4.4\nnameserver 1.1.1.1\noptions timeout:1 rotate\noptions attempts:3\n"); fclose(f); fprintf(stderr, "C DNS Cache: resolv.conf optimized\n"); }
}
int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    optimize_resolv_conf();
    while (running) { flush_dns_cache(); int i; for (i = 0; i < 1800 && running; i++) sleep(1); }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-dnscache /tmp/dns_cache.c 2>/dev/null
    rm -f /tmp/dns_cache.c
    
    if [ -f /usr/local/bin/elite-x-dnscache ]; then
        chmod +x /usr/local/bin/elite-x-dnscache
        cat > /etc/systemd/system/elite-x-dnscache.service <<EOF
[Unit]
Description=ELITE-X C DNS Cache Optimizer
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-dnscache
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C DNS Cache Optimizer compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED RAM CACHE CLEANER
# ═══════════════════════════════════════════════════════════
create_c_ram_cleaner() {
    echo -e "${YELLOW}📝 Compiling C RAM Cache Cleaner...${NC}"
    
    cat > /tmp/ram_cleaner.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
void clean_memory() {
    system("sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null");
    system("swapoff -a 2>/dev/null && swapon -a 2>/dev/null");
    system("echo 1 > /proc/sys/vm/compact_memory 2>/dev/null");
    system("sysctl -w vm.swappiness=10 >/dev/null 2>&1");
    system("sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_ratio=10 >/dev/null 2>&1");
    system("sysctl -w vm.dirty_background_ratio=5 >/dev/null 2>&1");
    fprintf(stderr, "C RAM Cleaner: Memory cleaned\n");
}
int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) { clean_memory(); int i; for (i = 0; i < 900 && running; i++) sleep(1); }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-ramcleaner /tmp/ram_cleaner.c 2>/dev/null
    rm -f /tmp/ram_cleaner.c
    
    if [ -f /usr/local/bin/elite-x-ramcleaner ]; then
        chmod +x /usr/local/bin/elite-x-ramcleaner
        cat > /etc/systemd/system/elite-x-ramcleaner.service <<EOF
[Unit]
Description=ELITE-X C RAM Cache Cleaner
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-ramcleaner
Restart=always
RestartSec=30
CPUQuota=10%
MemoryMax=30M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C RAM Cleaner compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED IRQ AFFINITY OPTIMIZER
# ═══════════════════════════════════════════════════════════
create_c_irq_optimizer() {
    echo -e "${YELLOW}📝 Compiling C IRQ Affinity Optimizer...${NC}"
    
    cat > /tmp/irq_optimizer.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
void optimize_irq() {
    DIR *d = opendir("/proc/irq");
    if (!d) return;
    struct dirent *entry;
    while ((entry = readdir(d))) {
        if (entry->d_name[0] == '.') continue;
        char path[512];
        snprintf(path, sizeof(path), "/proc/irq/%s/smp_affinity", entry->d_name);
        FILE *f = fopen(path, "w");
        if (f) { fprintf(f, "ffffffff\n"); fclose(f); }
    }
    closedir(d);
    system("for i in /sys/class/net/eth*/queues/rx-*/rps_cpus; do echo ffffffff > $i 2>/dev/null; done");
    system("for i in /sys/class/net/ens*/queues/rx-*/rps_cpus; do echo ffffffff > $i 2>/dev/null; done");
    fprintf(stderr, "C IRQ Optimizer: IRQs distributed\n");
}
int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) { optimize_irq(); sleep(600); }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-irqopt /tmp/irq_optimizer.c 2>/dev/null
    rm -f /tmp/irq_optimizer.c
    
    if [ -f /usr/local/bin/elite-x-irqopt ]; then
        chmod +x /usr/local/bin/elite-x-irqopt
        cat > /etc/systemd/system/elite-x-irqopt.service <<EOF
[Unit]
Description=ELITE-X C IRQ Affinity Optimizer
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-irqopt
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C IRQ Optimizer compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED DATA USAGE MONITOR
# ═══════════════════════════════════════════════════════════
create_c_data_usage() {
    echo -e "${YELLOW}📝 Compiling C Data Usage Monitor...${NC}"
    
    cat > /tmp/data_usage.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) {
        DIR *user_dir = opendir("/etc/elite-x/users");
        if (!user_dir) { sleep(30); continue; }
        char current_month[8];
        time_t now = time(NULL);
        strftime(current_month, sizeof(current_month), "%Y-%m", localtime(&now));
        struct dirent *entry;
        while ((entry = readdir(user_dir))) {
            if (entry->d_name[0] == '.') continue;
            char bw_file[512];
            snprintf(bw_file, sizeof(bw_file), "/etc/elite-x/bandwidth/%s.usage", entry->d_name);
            long long total_bytes = 0;
            FILE *f = fopen(bw_file, "r");
            if (f) { fscanf(f, "%lld", &total_bytes); fclose(f); }
            double total_gb = total_bytes / 1073741824.0;
            char usage_file[512];
            snprintf(usage_file, sizeof(usage_file), "/etc/elite-x/data_usage/%s", entry->d_name);
            f = fopen(usage_file, "w");
            if (f) { time_t t = time(NULL); char *time_str = ctime(&t); time_str[strcspn(time_str, "\n")] = 0; fprintf(f, "month: %s\ntotal_gb: %.2f\nlast_updated: %s\n", current_month, total_gb, time_str); fclose(f); }
        }
        closedir(user_dir);
        sleep(30);
    }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-datausage-c /tmp/data_usage.c 2>/dev/null
    rm -f /tmp/data_usage.c
    
    if [ -f /usr/local/bin/elite-x-datausage-c ]; then
        chmod +x /usr/local/bin/elite-x-datausage-c
        cat > /etc/systemd/system/elite-x-datausage.service <<EOF
[Unit]
Description=ELITE-X C Monthly Data Usage Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-datausage-c
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Data Usage Monitor compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# C-BASED LOG CLEANER
# ═══════════════════════════════════════════════════════════
create_c_log_cleaner() {
    echo -e "${YELLOW}📝 Compiling C Log Cleaner...${NC}"
    
    cat > /tmp/log_cleaner.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
static volatile int running = 1;
void signal_handler(int sig) { running = 0; }
void clean_logs() {
    system("find /var/log -type f -name '*.log' -size +50M -exec truncate -s 0 {} \\; 2>/dev/null");
    system("journalctl --vacuum-size=50M 2>/dev/null");
    system("truncate -s 0 /var/log/syslog 2>/dev/null");
    system("truncate -s 0 /var/log/messages 2>/dev/null");
    system("truncate -s 0 /var/log/kern.log 2>/dev/null");
    system("truncate -s 0 /var/log/auth.log 2>/dev/null");
    system("find /var/log -name '*.gz' -mtime +3 -delete 2>/dev/null");
    system("find /var/log -name '*.1' -delete 2>/dev/null");
    system("find /var/log -name '*.old' -delete 2>/dev/null");
    fprintf(stderr, "C Log Cleaner: Logs cleaned\n");
}
int main() {
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    while (running) { clean_logs(); int i; for (i = 0; i < 3600 && running; i++) sleep(1); }
    return 0;
}
CEOF

    gcc -O3 -o /usr/local/bin/elite-x-logcleaner /tmp/log_cleaner.c 2>/dev/null
    rm -f /tmp/log_cleaner.c
    
    if [ -f /usr/local/bin/elite-x-logcleaner ]; then
        chmod +x /usr/local/bin/elite-x-logcleaner
        cat > /etc/systemd/system/elite-x-logcleaner.service <<EOF
[Unit]
Description=ELITE-X C Log Cleaner
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-logcleaner
Restart=always
RestartSec=30
CPUQuota=10%
MemoryMax=20M
[Install]
WantedBy=multi-user.target
EOF
        echo -e "${GREEN}✅ C Log Cleaner compiled${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════
# USER MANAGEMENT SCRIPT (IMPROVED)
# ═══════════════════════════════════════════════════════════
create_user_script() {
    cat > /usr/local/bin/elite-x-user <<'USEREOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';ORANGE='\033[0;33m'
LIGHT_RED='\033[1;31m';LIGHT_GREEN='\033[1;32m';PURPLE='\033[0;35m';GRAY='\033[0;90m';NC='\033[0m'

UD="/etc/elite-x/users"; USAGE_DB="/etc/elite-x/data_usage"; DD="/etc/elite-x/deleted"; BD="/etc/elite-x/banned"; CONN_DB="/etc/elite-x/connections"; BW_DIR="/etc/elite-x/bandwidth"; PID_DIR="$BW_DIR/pidtrack"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"
mkdir -p "$UD" "$USAGE_DB" "$DD" "$BD" "$CONN_DB" "$BW_DIR" "$PID_DIR"

get_connection_count() {
    local username="$1"; local count=0
    who | grep -qw "$username" 2>/dev/null && count=$(who | grep -wc "$username" 2>/dev/null)
    [ "$count" -eq 0 ] && count=$(ps aux | grep "sshd:" | grep "$username" | grep -v grep | grep -v "sshd:.*@notty" | wc -l)
    echo ${count:-0}
}

get_bandwidth_usage() {
    local username="$1"; local bw_file="$BW_DIR/${username}.usage"
    if [ -f "$bw_file" ]; then
        local total_bytes=$(cat "$bw_file" 2>/dev/null || echo 0)
        echo "scale=2; $total_bytes / 1073741824" | bc 2>/dev/null || echo "0.00"
    else echo "0.00"; fi
}

add_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}           CREATE SSH + DNS USER          ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    if id "$username" &>/dev/null; then echo -e "${RED}User already exists!${NC}"; return; fi
    
    read -p "$(echo -e $GREEN"Password [auto-generate]: "$NC)" password
    [ -z "$password" ] && password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8) && echo -e "${GREEN}🔑 Generated: ${YELLOW}$password${NC}"
    
    read -p "$(echo -e $GREEN"Expire (days) [30]: "$NC)" days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "${RED}Invalid days!${NC}"; return; }
    
    read -p "$(echo -e $GREEN"Connection limit [1]: "$NC)" conn_limit; conn_limit=${conn_limit:-1}
    [[ ! "$conn_limit" =~ ^[0-9]+$ ]] && conn_limit=1
    
    read -p "$(echo -e $GREEN"Bandwidth limit in GB (0 = unlimited) [0]: "$NC)" bandwidth_gb; bandwidth_gb=${bandwidth_gb:-0}
    [[ ! "$bandwidth_gb" =~ ^[0-9]+\.?[0-9]*$ ]] && bandwidth_gb=0
    
    useradd -m -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    expire_date=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expire_date" "$username"
    
    cat > "$UD/$username" <<INFO
Username: $username
Password: $password
Expire: $expire_date
Conn_Limit: $conn_limit
Bandwidth_GB: $bandwidth_gb
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO
    
    echo "0" > "$BW_DIR/${username}.usage"
    
    # Force create user message
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    
    local bw_disp="Unlimited"; [ "$bandwidth_gb" != "0" ] && bw_disp="${bandwidth_gb} GB"
    SERVER=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "?")
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "?")
    PUBKEY=$(cat /etc/elite-x/public_key 2>/dev/null || echo "?")
    
    clear
    echo -e "${GREEN}╔═════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}          USER CREATED SUCCESSFULLY                    ${GREEN}║${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Username   :${CYAN} $username${NC}"
    echo -e "${GREEN}║${WHITE}  Password   :${CYAN} $password${NC}"
    echo -e "${GREEN}║${WHITE}  Server     :${CYAN} $SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $PUBKEY${NC}"
    echo -e "${GREEN}║${WHITE}  Expire     :${CYAN} $expire_date${NC}"
    echo -e "${GREEN}║${WHITE}  Max Login  :${CYAN} $conn_limit${NC}"
    echo -e "${GREEN}║${WHITE}  Bandwidth  :${CYAN} $bw_disp${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${YELLOW}  SLOWDNS CONFIG:${NC}"
    echo -e "${GREEN}║${WHITE}  NS: ${CYAN}$SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  PUBKEY: ${CYAN}$PUBKEY${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════════╝${NC}"
}

list_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                ACTIVE USERS               ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    
    if [ -z "$(ls -A "$UD" 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}                                    No users found                                          ${CYAN}${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
        return
    fi
    
    printf "${CYAN}║${WHITE} %-14s %-12s %-8s %-14s %-18s${CYAN} ║${NC}\n" "USERNAME" "EXPIRE" "LOGIN" "BANDWIDTH" "STATUS"
    echo -e "${CYAN}╟────────────────────────────────────────────────────────────╢${NC}"
    
    for user in "$UD"/*; do
        [ ! -f "$user" ] && continue
        u=$(basename "$user")
        ex=$(grep "Expire:" "$user" | cut -d' ' -f2)
        limit=$(grep "Conn_Limit:" "$user" | awk '{print $2}'); limit=${limit:-1}
        bw_limit=$(grep "Bandwidth_GB:" "$user" | awk '{print $2}'); bw_limit=${bw_limit:-0}
        
        total_gb=$(get_bandwidth_usage "$u")
        current_conn=$(get_connection_count "$u")
        
        expire_ts=$(date -d "$ex" +%s 2>/dev/null || echo 0)
        current_ts=$(date +%s)
        days_left=$(( (expire_ts - current_ts) / 86400 ))
        
        if passwd -S "$u" 2>/dev/null | grep -q "L"; then status="${RED}🔒 LOCKED${NC}"
        elif [ "$current_conn" -gt 0 ]; then status="${LIGHT_GREEN}🟢 ONLINE${NC}"
        elif [ $days_left -le 0 ]; then status="${RED}⛔ EXPIRED${NC}"
        elif [ $days_left -le 3 ]; then status="${LIGHT_RED}⚠️ CRITICAL${NC}"
        elif [ $days_left -le 7 ]; then status="${YELLOW}⚠️ WARNING${NC}"
        else status="${YELLOW}⚫ OFFLINE${NC}"; fi
        
        if [ "$bw_limit" != "0" ] && [ -n "$bw_limit" ]; then
            bw_percent=$(echo "scale=1; ($total_gb / $bw_limit) * 100" | bc 2>/dev/null || echo "0")
            if [ "$(echo "$bw_percent >= 100" | bc 2>/dev/null)" = "1" ]; then bw_display="${RED}${total_gb}/${bw_limit}GB${NC}"
            elif [ "$(echo "$bw_percent > 80" | bc 2>/dev/null)" = "1" ]; then bw_display="${YELLOW}${total_gb}/${bw_limit}GB${NC}"
            else bw_display="${GREEN}${total_gb}/${bw_limit}GB${NC}"; fi
        else bw_display="${GRAY}${total_gb}GB/∞${NC}"; fi
        
        [ "$current_conn" -ge "$limit" ] && login_display="${RED}${current_conn}/${limit}${NC}" || login_display="${GREEN}${current_conn}/${limit}${NC}"
        [ "$current_conn" -eq 0 ] && login_display="${GRAY}0/${limit}${NC}"
        [ $days_left -le 0 ] && exp_display="${RED}${ex}${NC}" || exp_display="${GREEN}${ex}${NC}"
        [ $days_left -le 7 ] && [ $days_left -gt 0 ] && exp_display="${YELLOW}${ex}${NC}"
        
        printf "${CYAN}║${WHITE} %-14s %-12b %-8b %-14b %-18b${CYAN} ║${NC}\n" "$u" "$exp_display" "$login_display" "$bw_display" "$status"
    done
    
    TOTAL_USERS=$(ls "$UD" 2>/dev/null | wc -l)
    TOTAL_ONLINE=$(who | wc -l)
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${YELLOW}  Users: ${GREEN}${TOTAL_USERS}${YELLOW} | Online: ${GREEN}${TOTAL_ONLINE}${NC}                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}User not found!${NC}"; return; }
    read -p "$(echo -e $GREEN"Additional days: "$NC)" days
    current_expire=$(grep "Expire:" "$UD/$username" | cut -d' ' -f2)
    new_expire=$(date -d "$current_expire +$days days" +"%Y-%m-%d")
    sed -i "s/Expire: .*/Expire: $new_expire/" "$UD/$username"
    chage -E "$new_expire" "$username" 2>/dev/null
    usermod -U "$username" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ User renewed until $new_expire${NC}"
}

set_bandwidth_limit() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}User not found!${NC}"; return; }
    current_bw=$(grep "Bandwidth_GB:" "$UD/$username" 2>/dev/null | awk '{print $2}')
    echo -e "${CYAN}Current: ${YELLOW}${current_bw:-Not set} GB${NC}"
    read -p "$(echo -e $GREEN"New limit (0=unlimited): "$NC)" new_bw
    [[ ! "$new_bw" =~ ^[0-9]+\.?[0-9]*$ ]] && { echo -e "${RED}Invalid!${NC}"; return; }
    grep -q "Bandwidth_GB:" "$UD/$username" && sed -i "s/Bandwidth_GB: .*/Bandwidth_GB: $new_bw/" "$UD/$username" || echo "Bandwidth_GB: $new_bw" >> "$UD/$username"
    [ "$new_bw" = "0" ] && usermod -U "$username" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth limit updated${NC}"
}

reset_bandwidth() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}User not found!${NC}"; return; }
    echo "0" > "$BW_DIR/${username}.usage"
    rm -rf "$PID_DIR/${username}" 2>/dev/null
    rm -f "$PID_DIR/${username}__"*.last 2>/dev/null
    usermod -U "$username" 2>/dev/null
    /usr/local/bin/elite-x-force-user-message "$username" 2>/dev/null
    echo -e "${GREEN}✅ Bandwidth reset to 0${NC}"
}

lock_user() { read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ] && { echo -e "${RED}User not found!${NC}"; return; }; usermod -L "$u" 2>/dev/null; pkill -u "$u" 2>/dev/null || true; echo "$(date) - MANUALLY LOCKED" >> "$BD/$u"; echo -e "${GREEN}✅ User locked${NC}"; }
unlock_user() { read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ] && { echo -e "${RED}User not found!${NC}"; return; }; usermod -U "$u" 2>/dev/null; echo "$(date) - MANUALLY UNLOCKED" >> "$BD/$u"; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ User unlocked${NC}"; }
delete_user() { read -p "$(echo -e $GREEN"Username: "$NC)" u; [ ! -f "$UD/$u" ] && { echo -e "${RED}User not found!${NC}"; return; }; cp "$UD/$u" "$DD/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null; pkill -u "$u" 2>/dev/null || true; killall -u "$u" -9 2>/dev/null || true; userdel -r "$u" 2>/dev/null; rm -f "$UD/$u" "$USAGE_DB/$u" "$CONN_DB/$u" "$BD/$u" "$BW_DIR/${u}.usage"; rm -rf "$PID_DIR/${u}" 2>/dev/null; rm -f "/etc/elite-x/user_messages/$u" 2>/dev/null; echo -e "${GREEN}✅ User deleted${NC}"; }

details_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    [ ! -f "$UD/$username" ] && { echo -e "${RED}User not found!${NC}"; return; }
    
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}              USER DETAILS                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    cat "$UD/$username" | while read line; do echo -e "${CYAN}║${WHITE}  $line${NC}"; done
    
    total_gb=$(get_bandwidth_usage "$username")
    bw_limit=$(grep "Bandwidth_GB:" "$UD/$username" 2>/dev/null | awk '{print $2}')
    bw_limit=${bw_limit:-0}
    current_conn=$(get_connection_count "$username")
    
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Active Sessions: ${GREEN}${current_conn}${NC}"
    echo -e "${CYAN}║${WHITE}  Bandwidth Used: ${GREEN}${total_gb} GB${NC} / ${YELLOW}${bw_limit:-Unlimited} GB${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
}

case $1 in
    add) add_user ;;
    list) list_users ;;
    details) details_user ;;
    renew) renew_user ;;
    setlimit) read -p "Username: " u; read -p "New limit: " l; [ -f "$UD/$u" ] && { sed -i "s/Conn_Limit: .*/Conn_Limit: $l/" "$UD/$u"; /usr/local/bin/elite-x-force-user-message "$u" 2>/dev/null; echo -e "${GREEN}✅ Updated${NC}"; } || echo -e "${RED}Not found${NC}" ;;
    setbw) set_bandwidth_limit ;;
    resetdata) reset_bandwidth ;;
    deleted) ls "$DD/" 2>/dev/null | head -20 || echo "No deleted users" ;;
    lock) lock_user ;;
    unlock) unlock_user ;;
    del) delete_user ;;
    *) echo "Usage: elite-x-user {add|list|details|renew|setlimit|setbw|resetdata|deleted|lock|unlock|del}" ;;
esac
USEREOF
    chmod +x /usr/local/bin/elite-x-user
}

# ═══════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════
create_main_menu() {
    cat > /usr/local/bin/elite-x <<'MENUEOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
PURPLE='\033[0;35m';WHITE='\033[1;37m';BOLD='\033[1m';NC='\033[0m'
ORANGE='\033[0;33m';LIGHT_RED='\033[1;31m';LIGHT_GREEN='\033[1;32m';GRAY='\033[0;90m'

UD="/etc/elite-x/users"; BW_DIR="/etc/elite-x/bandwidth"; AUTOBAN_FLAG="/etc/elite-x/autoban_enabled"

show_dashboard() {
    clear
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || echo "Unknown")
    SUB=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not set")
    LOCATION=$(cat /etc/elite-x/location 2>/dev/null || echo "South Africa")
    MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "1800")
    RAM=$(free -h | awk '/^Mem:/{print $3"/"$2}')
    
    # Check Server Message system
    if [ -f /usr/local/bin/elite-x-force-user-message ] && [ -d /etc/elite-x/user_messages ]; then
        SMSG="${GREEN}✅ Active${NC}"
    else
        SMSG="${RED}❌ Inactive${NC}"
    fi
    
    DNS=$(systemctl is-active dnstt-elite-x 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    PRX=$(systemctl is-active dnstt-elite-x-proxy 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    BW=$(systemctl is-active elite-x-bandwidth 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    NBOOST=$(systemctl is-active elite-x-netbooster 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    DNSC=$(systemctl is-active elite-x-dnscache 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    RAMC=$(systemctl is-active elite-x-ramcleaner 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    IRQ=$(systemctl is-active elite-x-irqopt 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    
    TOTAL_USERS=$(ls -1 "$UD" 2>/dev/null | wc -l)
    ONLINE=$(who | wc -l)
    
    TOTAL_BW=0
    if [ -d "$BW_DIR" ]; then
        for f in "$BW_DIR"/*.usage; do
            [ -f "$f" ] || continue
            b=$(cat "$f" 2>/dev/null || echo 0)
            gb=$(echo "scale=2; $b / 1073741824" | bc 2>/dev/null || echo "0")
            TOTAL_BW=$(echo "$TOTAL_BW + $gb" | bc 2>/dev/null || echo "$TOTAL_BW")
        done
    fi
    
    echo -e "${PURPLE}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${YELLOW}${BOLD}          ELITE-X v3.6 - FALCON           ${PURPLE}║${NC}"
    echo -e "${PURPLE}╠═════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${PURPLE}║${WHITE}  NS        :${GREEN} $SUB${NC}"
    echo -e "${PURPLE}║${WHITE}  IP        :${GREEN} $IP${NC}"
    echo -e "${PURPLE}║${WHITE}  Location  :${GREEN} $LOCATION (MTU: $MTU)${NC}"
    echo -e "${PURPLE}║${WHITE}  RAM       :${GREEN} $RAM${NC}"
    echo -e "${PURPLE}║${WHITE}  Core      : DNS:$DNS PRX:$PRX BW:$BW${NC}"
    echo -e "${PURPLE}║${WHITE}  Boosters  : NET:$NBOOST DNS:$DNSC RAM:$RAMC IRQ:$IRQ${NC}"
    echo -e "${PURPLE}║${WHITE}  User Msg   : $SMSG${NC}"
    echo -e "${PURPLE}║${WHITE}  Users     :${GREEN} $TOTAL_USERS total, $ONLINE online${NC}"
    echo -e "${PURPLE}║${WHITE}  Total BW  :${YELLOW} ${TOTAL_BW} GB${NC}"
    echo -e "${PURPLE}╚═════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

settings_menu() {
    while true; do
        clear
        autoban=$(cat "$AUTOBAN_FLAG" 2>/dev/null || echo "0")
        [ "$autoban" = "1" ] && ABSTATUS="${RED}ENABLED${NC}" || ABSTATUS="${GREEN}DISABLED${NC}"
        
        echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║${YELLOW}${BOLD}                  SETTINGS MENU                     ${PURPLE}║${NC}"
        echo -e "${PURPLE}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${PURPLE}║${WHITE}  [1] Change MTU  [2] Speed Optimize  [3] Clean Cache${NC}"
        echo -e "${PURPLE}║${WHITE}  [4] Edit Msg     [5] Reset Msg       [6] Traffic Stats${NC}"
        echo -e "${PURPLE}║${WHITE}  [7] Reset All BW [8] Toggle Auto-Ban ($ABSTATUS)${WHITE}${NC}"
        echo -e "${PURPLE}║${WHITE}  [9] Restart All  [10] Reboot VPS      [11] Uninstall${NC}"
        echo -e "${PURPLE}║${WHITE}  [12] Recompile C   [13] Fix VPN/SSH    [14] Refresh Msg All${NC}"
        echo -e "${PURPLE}║${WHITE}  [15] Test Msg     [0] Back${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch
        
        case $ch in
            1)
                read -p "New MTU (1000-5000): " mtu
                [[ "$mtu" =~ ^[0-9]+$ ]] && [ $mtu -ge 1000 ] && [ $mtu -le 5000 ] && {
                    echo "$mtu" > /etc/elite-x/mtu
                    sed -i "s/-mtu [0-9]*/-mtu $mtu/" /etc/systemd/system/dnstt-elite-x.service
                    systemctl daemon-reload
                    systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                    echo -e "${GREEN}✅ MTU updated${NC}"
                } || echo -e "${RED}Invalid${NC}"
                read -p "Press Enter..." ;;
            2) 
                sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
                sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
                sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
                sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
                sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
                sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
                systemctl restart elite-x-netbooster 2>/dev/null
                echo -e "${GREEN}✅ Speed optimized${NC}"
                read -p "Press Enter..." ;;
            3) 
                sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                systemctl restart elite-x-ramcleaner elite-x-dnscache 2>/dev/null
                echo -e "${GREEN}✅ Cache cleaned${NC}"
                read -p "Press Enter..." ;;
            4) 
                echo -e "${YELLOW}Editing custom message for specific user:${NC}"
                read -p "Username: " uname
                if [ -f "/etc/elite-x/user_messages/$uname" ]; then
                    nano "/etc/elite-x/user_messages/$uname"
                    systemctl reload sshd
                    echo -e "${GREEN}✅ Message updated for $uname${NC}"
                else
                    echo -e "${RED}User not found or no message file!${NC}"
                fi
                read -p "Press Enter..." ;;
            5) 
                read -p "Reset message for which user? (all for all users): " uname
                if [ "$uname" = "all" ]; then
                    for u in "$UD"/*; do
                        [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")" 2>/dev/null
                    done
                else
                    /usr/local/bin/elite-x-force-user-message "$uname" 2>/dev/null
                fi
                systemctl reload sshd
                echo -e "${GREEN}✅ Messages reset${NC}"
                read -p "Press Enter..." ;;
            6) 
                iface=$(ip route | grep default | awk '{print $5}' | head -1)
                rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
                tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
                echo -e "RX: $(echo "scale=2; $rx/1073741824" | bc) GB"
                echo -e "TX: $(echo "scale=2; $tx/1073741824" | bc) GB"
                read -p "Press Enter..." ;;
            7) 
                for f in "$BW_DIR"/*.usage; do [ -f "$f" ] && echo "0" > "$f"; done
                for u in "$UD"/*; do [ -f "$u" ] && usermod -U "$(basename "$u")" 2>/dev/null; done
                echo -e "${GREEN}✅ All bandwidth reset${NC}"
                read -p "Press Enter..." ;;
            8)
                [ "$autoban" = "1" ] && echo "0" > "$AUTOBAN_FLAG" || echo "1" > "$AUTOBAN_FLAG"
                systemctl restart elite-x-connmon 2>/dev/null
                echo -e "${GREEN}✅ Toggled${NC}"
                read -p "Press Enter..." ;;
            9) 
                for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner sshd; do
                    systemctl restart "$s" 2>/dev/null || true
                done
                echo -e "${GREEN}✅ All services restarted${NC}"
                read -p "Press Enter..." ;;
            10) read -p "Reboot? (y/n): " c; [ "$c" = "y" ] && reboot ;;
            11)
                read -p "Type 'YES' to confirm uninstall: " c
                [ "$c" = "YES" ] && {
                    for u in "$UD"/*; do
                        [ -f "$u" ] && { un=$(basename "$u"); pkill -u "$un" 2>/dev/null; userdel -r "$un" 2>/dev/null; }
                    done
                    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner; do
                        systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null
                    done
                    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*}
                    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x
                    rm -f /usr/local/bin/{dnstt-*,elite-x*}
                    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf
                    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
                    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd
                    systemctl restart sshd 2>/dev/null
                    rm -f /etc/profile.d/elite-x-dashboard.sh
                    sed -i '/elite-x/d' ~/.bashrc 2>/dev/null
                    rm -f /etc/sysctl.d/99-elite-x-vpn.conf
                    systemctl daemon-reload
                    echo -e "${GREEN}✅ Uninstalled!${NC}"
                    exit 0
                }
                read -p "Press Enter..." ;;
            12)
                echo -e "${YELLOW}Recompiling all C boosters...${NC}"
                optimize_system_for_vpn
                create_c_edns_proxy
                create_c_bandwidth_monitor
                create_c_connection_monitor
                create_c_network_booster
                create_c_dns_cache
                create_c_ram_cleaner
                create_c_irq_optimizer
                create_c_log_cleaner
                create_c_data_usage
                systemctl daemon-reload
                for s in dnstt-elite-x-proxy elite-x-bandwidth elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner elite-x-datausage; do
                    systemctl restart "$s" 2>/dev/null || true
                done
                echo -e "${GREEN}✅ All C boosters recompiled${NC}"
                read -p "Press Enter..." ;;
            13)
                echo -e "${YELLOW}Fixing VPN/SSH configuration...${NC}"
                configure_ssh_for_vpn
                systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd 2>/dev/null
                echo -e "${GREEN}✅ VPN/SSH fixed${NC}"
                read -p "Press Enter..." ;;
            14)
                echo -e "${YELLOW}Refreshing messages for all users...${NC}"
                for user in "$UD"/*; do
                    [ -f "$user" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$user")" 2>/dev/null
                done
                systemctl reload sshd
                echo -e "${GREEN}✅ Messages refreshed!${NC}"
                read -p "Press Enter..." ;;
            15)
                read -p "Test message for which user? " uname
                if [ -f "/etc/elite-x/user_messages/$uname" ]; then
                    echo -e "${CYAN}Message for $uname:${NC}"
                    echo -e "${WHITE}───────────────────────────────────────${NC}"
                    cat "/etc/elite-x/user_messages/$uname"
                    echo -e "${WHITE}───────────────────────────────────────${NC}"
                else
                    echo -e "${RED}No message found!${NC}"
                fi
                read -p "Press Enter..." ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        
        echo -e "${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║${GREEN}${BOLD}                    MAIN MENU v3.6                     ${PURPLE}║${NC}"
        echo -e "${PURPLE}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${PURPLE}║${WHITE}  [1] Create User   [2] List Users      [3] User Details${NC}"
        echo -e "${PURPLE}║${WHITE}  [4] Renew User    [5] Set Conn Limit   [6] Set BW Limit${NC}"
        echo -e "${PURPLE}║${WHITE}  [7] Reset BW      [8] Lock User        [9] Unlock User${NC}"
        echo -e "${PURPLE}║${WHITE}  [10] Delete User  [11] Deleted List     [S] Settings${NC}"
        echo -e "${PURPLE}║${WHITE}  [M] Test Msg      [0] Exit${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
        read -p "$(echo -e $GREEN"Option: "$NC)" ch
        
        case $ch in
            1) elite-x-user add; read -p "Press Enter..." ;;
            2) elite-x-user list; read -p "Press Enter..." ;;
            3) elite-x-user details; read -p "Press Enter..." ;;
            4) elite-x-user renew; read -p "Press Enter..." ;;
            5) elite-x-user setlimit; read -p "Press Enter..." ;;
            6) elite-x-user setbw; read -p "Press Enter..." ;;
            7) elite-x-user resetdata; read -p "Press Enter..." ;;
            8) elite-x-user lock; read -p "Press Enter..." ;;
            9) elite-x-user unlock; read -p "Press Enter..." ;;
            10) elite-x-user del; read -p "Press Enter..." ;;
            11) elite-x-user deleted; read -p "Press Enter..." ;;
            [Ss]) settings_menu ;;
            [Mm]) 
                read -p "Username: " uname
                if [ -f "/etc/elite-x/user_messages/$uname" ]; then
                    clear
                    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
                    echo -e "${CYAN}║${YELLOW}       USER MESSAGE PREVIEW FOR $uname                    ${CYAN}║${NC}"
                    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
                    cat "/etc/elite-x/user_messages/$uname"
                    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
                else
                    echo -e "${RED}No message found for $uname!${NC}"
                fi
                read -p "Press Enter..." ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid${NC}"; read -p "Press Enter..." ;;
        esac
    done
}

main_menu
MENUEOF
    chmod +x /usr/local/bin/elite-x
}

# ═══════════════════════════════════════════════════════════
# MAIN INSTALLATION
# ═══════════════════════════════════════════════════════════

# FUNCTION to run installation without set -e
run_installation() {
    show_banner
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${GREEN}            ACTIVATION REQUIRED          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

    if [ "$ACTIVATION_INPUT" != "$ACTIVATION_KEY" ] && [ "$ACTIVATION_INPUT" != "Whtsapp +255713-628-668" ]; then
        echo -e "${RED}❌ Invalid activation key!${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Activation successful${NC}"
    sleep 1

    set_timezone

    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           ENTER YOUR NAMESERVER [NS]      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    read -p "$(echo -e $GREEN"Nameserver: "$NC)" TDOMAIN

    echo -e "${YELLOW}Select VPS location:${NC}"
    echo -e "  [1] South Africa (MTU 1800)"
    echo -e "  [2] USA (MTU 1500)"
    echo -e "  [3] Europe (MTU 1500)"
    echo -e "  [4] Asia (MTU 1400)"
    echo -e "  [5] Custom MTU"
    read -p "$(echo -e $GREEN"Choice [1]: "$NC)" LOC
    LOC=${LOC:-1}
    case $LOC in
        2) SEL_LOC="USA"; MTU=1500 ;;
        3) SEL_LOC="Europe"; MTU=1500 ;;
        4) SEL_LOC="Asia"; MTU=1400 ;;
        5) SEL_LOC="Custom"; read -p "MTU: " MTU; [[ ! "$MTU" =~ ^[0-9]+$ ]] && MTU=1800 ;;
        *) SEL_LOC="South Africa"; MTU=1800 ;;
    esac

    echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"
    for s in dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon elite-x-cleaner elite-x-traffic elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner 3proxy-elite; do
        systemctl stop "$s" 2>/dev/null || true
        systemctl disable "$s" 2>/dev/null || true
    done
    pkill -f dnstt-server 2>/dev/null || true
    pkill -f elite-x-edns-proxy 2>/dev/null || true
    rm -rf /etc/systemd/system/{dnstt-elite-x*,elite-x*,3proxy-elite*} 2>/dev/null
    rm -rf /etc/dnstt /etc/elite-x /var/run/elite-x 2>/dev/null
    rm -f /usr/local/bin/{dnstt-*,elite-x*,3proxy} 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf 2>/dev/null
    sed -i '/^Match User/,/Banner/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d\/\*\.conf/d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x-update-user-msg/d' /etc/pam.d/sshd 2>/dev/null
    systemctl restart sshd 2>/dev/null || true
    sleep 2

    # Create directories
    mkdir -p /etc/elite-x/{users,traffic,deleted,data_usage,connections,banned,traffic_stats,bandwidth/pidtrack,user_messages}
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p /var/run/elite-x/bandwidth
    echo "$TDOMAIN" > /etc/elite-x/subdomain
    echo "$SEL_LOC" > /etc/elite-x/location
    echo "$MTU" > /etc/elite-x/mtu
    echo "0" > "$AUTOBAN_FLAG"
    echo "$STATIC_PRIVATE_KEY" > /etc/elite-x/private_key
    echo "$STATIC_PUBLIC_KEY" > /etc/elite-x/public_key

    # Configure DNS
    [ -f /etc/systemd/resolved.conf ] && {
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null || true
    }
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf

    # Install dependencies
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    apt update -y
    apt install -y curl jq iptables ethtool dnsutils net-tools iproute2 bc build-essential git gcc make 2>/dev/null

    # Setup C compiler
    echo -e "${YELLOW}🔧 Setting up C compiler environment...${NC}"
    apt-get install -y gcc make build-essential 2>/dev/null
    echo -e "${GREEN}✅ C compiler ready${NC}"

    # Download DNSTT
    echo -e "${YELLOW}📥 Downloading DNSTT server...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || {
        curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null
    }
    chmod +x /usr/local/bin/dnstt-server

    # Setup DNSTT keys
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY" > /etc/dnstt/server.pub
    chmod 600 /etc/dnstt/server.key

    # Create DNSTT service
    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server v3.6
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :5300 -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=5
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
EOF

    # Optimize system
    optimize_system_for_vpn

    # Configure PAM + user message system (BEFORE SSH)
    configure_pam_user_message

    # Configure SSH with user messages
    configure_ssh_for_vpn

    # Create C-based components
    create_c_edns_proxy

    if [ -f /usr/local/bin/elite-x-edns-proxy ]; then
        cat > /etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=ELITE-X C EDNS Proxy (Fixed)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns-proxy
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
    fi

    create_c_bandwidth_monitor
    create_c_connection_monitor
    create_c_data_usage
    create_c_network_booster
    create_c_dns_cache
    create_c_ram_cleaner
    create_c_irq_optimizer
    create_c_log_cleaner

    # Create user scripts
    create_user_script
    create_main_menu

    # Enable and start all services
    systemctl daemon-reload

    ALL_SERVICES=(dnstt-elite-x dnstt-elite-x-proxy elite-x-bandwidth elite-x-datausage elite-x-connmon elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt elite-x-logcleaner)

    for s in "${ALL_SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/${s}.service" ]; then
            systemctl enable "$s" 2>/dev/null || true
            systemctl start "$s" 2>/dev/null || true
        fi
    done

    # Cache IP
    IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
    echo "$IP" > /etc/elite-x/cached_ip

    # Setup auto-login dashboard
    cat > /etc/profile.d/elite-x-dashboard.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_SHOWN" ]; then
    export ELITE_X_SHOWN=1
    /usr/local/bin/elite-x
fi
EOF
    chmod +x /etc/profile.d/elite-x-dashboard.sh

    # Add aliases
    cat >> ~/.bashrc <<'EOF'
alias menu='elite-x'
alias elitex='elite-x'
alias adduser='elite-x-user add'
alias users='elite-x-user list'
alias setbw='elite-x-user setbw'
alias boost='systemctl restart elite-x-netbooster elite-x-dnscache elite-x-ramcleaner elite-x-irqopt'
alias fixvpn='systemctl restart dnstt-elite-x dnstt-elite-x-proxy sshd && echo "VPN Fixed!"'
alias refreshmsg='for u in /etc/elite-x/users/*; do [ -f "$u" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$u")"; done && systemctl reload sshd && echo "✅ Messages refreshed!"'
alias testmsg='read -p "Username: " u; cat /etc/elite-x/user_messages/$u 2>/dev/null || echo "No message"'
EOF

    # Create initial messages for any existing users (if any - none yet)
    for user_file in /etc/elite-x/users/*; do
        [ -f "$user_file" ] && /usr/local/bin/elite-x-force-user-message "$(basename "$user_file")" 2>/dev/null
    done

    # ═══════════════════════════════════════════════════════════
    # FINAL DISPLAY
    # ═══════════════════════════════════════════════════════════
    clear
    echo -e "${GREEN}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}${BOLD}       ELITE-X v3.6 FALCON  INSTALLED!  ${GREEN}║${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Domain     :${CYAN} $TDOMAIN${NC}"
    echo -e "${GREEN}║${WHITE}  Location   :${CYAN} $SEL_LOC (MTU: $MTU)${NC}"
    echo -e "${GREEN}║${WHITE}  IP         :${CYAN} $IP${NC}"
    echo -e "${GREEN}║${WHITE}  Version    :${CYAN} v3.6 Falcon Ultra ${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key :${CYAN} $STATIC_PUBLIC_KEY${NC}"
    echo -e "${GREEN}╠═════════════════════════════════════════════════════════════╣${NC}"

    # Check services (all systemd services only)
    check_svc() {
        local name=$1
        local service=$2
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}║  ✅ $name: Running${NC}"
        else
            echo -e "${RED}║  ❌ $name: Failed${NC}"
        fi
    }

    check_svc "DNSTT Server     " "dnstt-elite-x"
    check_svc "C EDNS Proxy     " "dnstt-elite-x-proxy"
    check_svc "SSH Server       " "sshd"
    check_svc "C Bandwidth Mon  " "elite-x-bandwidth"
    check_svc "C Conn Monitor   " "elite-x-connmon"
    check_svc "C Net Booster    " "elite-x-netbooster"
    check_svc "C DNS Cache      " "elite-x-dnscache"
    check_svc "C RAM Cleaner    " "elite-x-ramcleaner"
    check_svc "C IRQ Optimizer  " "elite-x-irqopt"
    check_svc "C Log Cleaner    " "elite-x-logcleaner"

    # User message check (file-based, not service)
    if [ -f /usr/local/bin/elite-x-force-user-message ] && [ -d /etc/elite-x/user_messages ]; then
        echo -e "${GREEN}║  ✅ User Message    : Active (on SSH login)${NC}"
    else
        echo -e "${RED}║  ❌ User Message    : Inactive${NC}"
    fi

    echo -e "${GREEN}╚═════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Commands: menu | elite-x | users | adduser | setbw | boost | fixvpn | refreshmsg | testmsg${NC}"
    echo -e "${YELLOW}Re-login or type 'exec bash' to access the dashboard${NC}"
    echo ""
    echo -e "${CYAN}═══ USER MESSAGE FEATURE (FIXED) ═══${NC}"
    echo -e "${WHITE}✅ Kila user anapoconnect SSH anaona DETAILS ZAKE moja kwa moja:${NC}"
    echo -e "${WHITE}  👤 USERNAME • 📅 EXPIRE • ⏳ REMAINING (Xday + Yhr)${NC}"
    echo -e "${WHITE}  📊 LIMIT GB • 💾 USAGE GB • 🔗 CONNECTIONS${NC}"
    echo -e "${WHITE}✅ PAM inaupdate message automatik kwenye kila login${NC}"
    echo -e "${WHITE}✅ SSH Match User inaforce banner ya user maalum${NC}"
    echo ""
    echo -e "${CYAN}SLOWDNS CONFIG FOR CLIENT:${NC}"
    echo -e "${WHITE}  NS     : ${GREEN}$TDOMAIN${NC}"
    echo -e "${WHITE}  PUBKEY : ${GREEN}$STATIC_PUBLIC_KEY${NC}"
    echo -e "${WHITE}  PORT   : ${GREEN}53${NC}"
    echo ""
}

# Run installation
run_installation