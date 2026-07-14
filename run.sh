#!/usr/bin/env bash

set -euuo pipefail

if (( EUID != 0 )); then
	echo "Please run as root!" >&2
	exit 1
fi

sudo apt-get update
sudo apt-get install -y curl wget aria2 jq kiwix-tools ca-certificates gnupg lsb-release
#Create kiwix dir
KIWIX_DIR="/home/${SUDO_USER}/Desktop/Kiwix-zims"
if [[ ! -d "$KIWIX_DIR" ]]; then
	mkdir -p "$KIWIX_DIR" && chown "$SUDO_USER:$SUDO_USER" "$KIWIX_DIR"
fi

QL_FILE="/home/${SUDO_USER}/Desktop/Quick Links.txt"
if [[ ! -f "$QL_FILE" ]]; then
	bash -c "cat > '$QL_FILE' <<EOF
	Download zims from here: library.kiwix.org
	Download websites and turn them into zims here: zimit.kiwix.org/
	When downloading zims, place them into the Kiwix-zims folder in your Documents
	Open Kiwix > Select the three dots in the top right hand corner > Settings > Browse > Documents > Kiwix-zims
	Select Ok
	Now Kiwix will look at that folder for any new zim's you add!
	EOF" && chown "$SUDO_USER:$SUDO_USER" "$QL_FILE"
fi

#Install and setup ufw
apt install ufw -y
ufw --force enable
ufw allow 8080/tcp

#Install docker
if ! command -v docker &> /dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -y -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$CODENAME") stable" | tee /etc/apt/sources.list.p/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

#Install Ollama and model qwen3.5:0.8b
if [[ ! -d "/usr/share/ollama" ]]; then
	curl -fsSL https://ollama.com/install.sh | sh
	export PATH="$HOME/.ollama/bin:$PATH"
fi
if [[ ! -f "/usr/share/ollama/.ollama/models/manifests/registry.ollama.ai/library/qwen3.5" ]]; then 
	sudo ollama pull qwen3.5:0.8b
fi

#Get the Wikipedia library from kiwix web
#For the sake of the example and memory we will download a smaller version of the library (3.2GB instead of ~50GB)
#aria2c way faster than wget
ZIM_NAME="wikipedia_en-simple_all_maxi_2026-06"
ZIM_FILE="${KIWIX_DIR}/${ZIM_NAME}.zim"

if [[ ! -f "$ZIM_FILE" ]]; then
    echo "Downloading Wikipedia ZIM file..."
    aria2c -x 4 -s 4 "https://lb.download.kiwix.org/zim/wikipedia/${ZIM_NAME}.zim" -d "$KIWIX_DIR"
    chown "$SUDO_USER:$SUDO_USER" "$ZIM_FILE"
fi

#Set-up the wikipedia page on localhost:8080

#Set up Kiwix systemd service
cat <<EOF > /etc/systemd/system/kiwix.service
[Unit]
Description=Kiwix Offline Wikipedia Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/kiwix-serve --port=8080 --listen=127.0.0.1 "/home/${SUDO_USER}/Desktop/Kiwix-zims/wikipedia_en-simple_all_maxi_2026-06.zim"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

#Reload and start the service
systemctl daemon-reload
systemctl enable kiwix.service
systemctl start kiwix.service

#Open WebUI for RetrievalAugmentedGeneration 
docker run -d -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo -e "Set-up done!"
	
