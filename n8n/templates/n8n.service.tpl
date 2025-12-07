[Unit]
Description=n8n Automation Service
After=network.target

[Service]
ExecStart=${N8N_EXEC}
Restart=always
User=${USER_NAME}
Environment=NODE_ENV=production
WorkingDirectory=${USER_HOME}

[Install]
WantedBy=multi-user.target
