#!/bin/bash

# Nome do contêiner onde os backups estão armazenados
CONTAINER_NAME="zammad-backup"
BACKUP_DIR="/var/tmp/zammad"
DEST_DIR="./dump"

# Verifica se o diretório de destino existe, se não, cria
mkdir -p "$DEST_DIR"

# Lista os arquivos de backup disponíveis no contêiner
echo "--- Listando backups disponíveis no contêiner $CONTAINER_NAME..."
docker compose exec "$CONTAINER_NAME" ls -lh "$BACKUP_DIR"

# Solicita que o usuário escolha um arquivo
echo ""
read -p "Digite o nome do arquivo que deseja copiar (exemplo: 20250205170153_zammad_db.psql.gz): " BACKUP_FILE

# Verifica se o arquivo foi informado
if [ -z "$BACKUP_FILE" ]; then
    echo "Nenhum arquivo foi informado. Saindo..."
    exit 1
fi

# Copia o backup do contêiner para o host
echo "-- Copiando o arquivo $BACKUP_FILE para $DEST_DIR..."
docker compose cp "$CONTAINER_NAME:$BACKUP_DIR/$BACKUP_FILE" "$DEST_DIR/"

# Verifica se a cópia foi bem-sucedida
if [ $? -eq 0 ]; then
    echo "Backup copiado com sucesso para $DEST_DIR/$BACKUP_FILE"
else
    echo "Erro ao copiar o backup!"
    exit 1
fi
