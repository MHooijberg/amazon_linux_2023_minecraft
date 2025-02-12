#!/bin/bash
# A script to automate the deployment of the AddSite CMS Application

# TODO: Create system service to start minecraft after boot
# TODO: Create safe way to close minecraft.
# TODO: Create screen session to reattach to minecraft application and send command programmatically.
# TODO: Auto attach to storage volume.
# TODO: Setup spot instances.

# START_COMMAND="java -Duser.language=en_US -XX:+UnlockExperimentalVMOptions -XX:+UseContainerSupport -XX:MaxRAMPercentage=100.0 -XX:+UseG1GC -jar ${DIR_SERVER_BASE}/server.jar nogui";

# TODO: Added temporarily:
sudo mkdir /mnt/server;
chown -R app-data:app-data /mnt/server;

export TYPE_PROJECT="paper";
export VERSION_MINECRAFT="1.21.4";
export TERM=xterm-256color;
export DIR_SERVER_BASE="/mnt/server";
export START_COMMAND_BASE="/usr/bin/java -Duser.language=en_US -Xmx1300M -Xms1300M -jar /mnt/server/server.jar nogui";
export START_COMMAND="/usr/bin/screen -dmS minecraft ${START_COMMAND_BASE}";
STOP_COMMAND="/usr/bin/screen -S minecraft -X stuff 'stop$(printf \"\r\")'";

# Update the packages, and clean dnf to keep image small.
echo "Updating, installing software, and cleaning up dnf...";
dnf upgrade -y && \
    dnf install -y findutils java-21-amazon-corretto-headless jq udev screen && \
    dnf autoremove && \
    dnf clean all;

# Add new user to run the Java application under
echo "Adding 'app-data' user.";
adduser -M --shell "/sbin/nologin" app-data;

# TODO: Temproarily added the following:
chown -R app-data:app-data /mnt/server;

# Check if the Minecraft server was setup already.
NO_JAR_FILE=$([ ! -f "${DIR_SERVER_BASE}/server.jar" ] && echo true || echo false);
echo "No existing server.jar found: ${NO_JAR_FILE}";

# Code below updates the jar file with the latest build.
LATEST_BUILD=$(curl -s https://api.papermc.io/v2/projects/${TYPE_PROJECT}/versions/${VERSION_MINECRAFT}/builds | \
    jq -r '.builds | map(select(.channel == "default") | .build) | .[-1]');

if [ "$LATEST_BUILD" != "null" ]; then
    echo "New stable build found: ${LATEST_BUILD}.";
    JAR_NAME=${TYPE_PROJECT}-${VERSION_MINECRAFT}-${LATEST_BUILD}.jar;
    PAPERMC_URL="https://api.papermc.io/v2/projects/${TYPE_PROJECT}/versions/${VERSION_MINECRAFT}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

    # Download the latest Paper version
    curl -Lo ${DIR_SERVER_BASE}/server.jar $PAPERMC_URL;
    echo "Download of new build completed.";
    # Ensure correct permissions for execution are set on the file.
    chmod 744 ${DIR_SERVER_BASE}/server.jar && chown app-data:app-data ${DIR_SERVER_BASE}/server.jar;
elif [ "$LATEST_BUILD" == "null" ] && $NO_JAR_FILE; then
    echo "No stable build for version $VERSION_MINECRAFT found. There's also no server.jar already present.";
    exit 1;
fi

# If the server.jar does not exist yet, execute the following.
if $NO_JAR_FILE; then
    echo "Setting up new server...";
    echo "Downloading new plugins...";
    mkdir /tmp/plugins;
    curl -Lo /tmp/plugins/EssentialsX-2.20.1.jar https://github.com/EssentialsX/Essentials/releases/download/2.20.1/EssentialsX-2.20.1.jar
    curl -Lo /tmp/plugins/EssentialsXChat-2.20.1.jar https://github.com/EssentialsX/Essentials/releases/download/2.20.1/EssentialsXChat-2.20.1.jar
    curl -Lo /tmp/plugins/EssentialsXSpawn-2.20.1.jar https://github.com/EssentialsX/Essentials/releases/download/2.20.1/EssentialsXSpawn-2.20.1.jar
    curl -Lo /tmp/plugins/EssentialsXDiscord-2.20.1.jar https://github.com/EssentialsX/Essentials/releases/download/2.20.1/EssentialsXDiscord-2.20.1.jar
    curl -Lo /tmp/plugins/bluemap-5.5-paper.jar https://github.com/BlueMap-Minecraft/BlueMap/releases/download/v5.5/bluemap-5.5-paper.jar

    # First run to populate the server folder
    echo "First boot to setup files...";
    cd /mnt/server
    $START_COMMAND_BASE

    # Accept nececarry files
    echo "Accepting eula.txt...";
    sed -i 's|eula=false|eula=true|' ${DIR_SERVER_BASE}/eula.txt;

    # Get the list of all files in /opt/plugins (excluding directories)
    PLUGINS=($(find "/tmp/plugins" -maxdepth 1 -type f -exec basename {} \;));

    # Move plugins to server plugins directory if they are not already there
    echo "Installing all new plugins to server...";
    for PLUGIN in "${PLUGINS[@]}"; do
        if [ -f "${DIR_SERVER_BASE}/plugins/$PLUGIN" ]; then
            continue;
        fi
        mkdir -p "${DIR_SERVER_BASE}/plugins/";
        mv "/tmp/plugins/$PLUGIN" "${DIR_SERVER_BASE}/plugins/";
        echo "New plugin ${PLUGIN} installed.";
    done
    rm -rf /tmp/plugins;
    echo "Removed residual (newly downloaded) plugins.";
fi

# Ensure correct permissions:
echo "Updating server file ownership...";
chown -R app-data:app-data /mnt/server;

# Create SystemD Script to run Minecraft server jar on reboot.
echo "Creating new SystemD service: minecraft.service...";
tee /etc/systemd/system/minecraft.service >/dev/null <<EOF
[Unit]
Description=Minecraft Server on startup
Wants=network-online.target
After=network-online.target

[Service]
User=app-data
WorkingDirectory=/mnt/server
ExecStart=${START_COMMAND}
ExecStop=${STOP_COMMAND}
Restart=on-failure
TimeoutStopSec=60
StandardOutput=append:/var/log/minecraft.log
StandardError=append:/var/log/minecraft.log

[Install]
WantedBy=multi-user.target
EOF

# Reload system services, enable minecraft service on bootup, and start the service.
echo "Reloading SystemD, enabling, and starting minecraft.service...";
sudo systemctl daemon-reload && \
    sudo systemctl enable minecraft.service && \
    sudo systemctl start minecraft.service;

echo "Done! Server should be all setup";

# Finally, execute the main command.
exec "$@"