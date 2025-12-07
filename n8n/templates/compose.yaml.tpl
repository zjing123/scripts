services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_VERSION}
    restart: always
    ports:
      - "127.0.0.1:${PORT}:5678"
    environment:
      - N8N_RUNNERS_ENABLED=true
    env_file:
      - .env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
volumes:
  n8n_data:

