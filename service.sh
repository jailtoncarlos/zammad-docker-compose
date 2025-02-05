#!/bin/bash

# Verifica se o primeiro argumento foi informado (dev ou prod)
if [ -z "$1" ]; then
    echo "ERRO: Você deve informar o ambiente (dev ou prod)."
    echo "Uso: $0 {dev|prod} {up|down|restart|logs|exec|ps|backup|restore} [args]"
    exit 1
fi

# Define os arquivos docker-compose com base no ambiente informado
ENVIRONMENT="$1"
shift  # Remove o primeiro argumento da lista

# Carregar variáveis do arquivo .env
export $(grep -v '^#' .env | xargs)

REDE=""
case "$ENVIRONMENT" in
    dev)
        COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose-dev.yml"
        echo "Usando ambiente de **desenvolvimento** (docker-compose-dev.yml)"
        REDE="zammad-network"
        ACESSO="http://localhost:8080"
        ;;
    prod)
        COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose-prod.yml"
        echo "Usando ambiente de **produção** (docker-compose-prod.yml)"
        REDE="proxy-network"
        ACESSO="https://seu-dominio.com"
        ;;
    *)
        echo "ERRO: Ambiente inválido! Escolha 'dev' ou 'prod'."
        exit 1
        ;;
esac

# Exibir uso do script
function usage() {
    echo "Uso: $0 {dev|prod} {up|down|restart|logs|exec|ps|backup|restore|copiar-backup} [args]"
    echo "  up             - Inicia os serviços em segundo plano"
    echo "  down           - Para e remove os containers"
    echo "  restart        - Reinicia os serviços"
    echo "  logs           - Exibe logs dos serviços"
    echo "  exec           - Executa um comando em um serviço específico"
    echo "  ps             - Lista os serviços em execução"
    echo "  backup         - Executa o backup do Zammad"
    echo "  restore        - Restaura um backup do Zammad"
    echo "  copiar-backup  - Copia o backup do Zammad do contêiner para o host"
    echo "  qualquer outro comando será passado diretamente para o docker-compose"
    exit 1
}

# Verifica se há argumentos suficientes
if [ $# -lt 1 ]; then
    usage
fi

# Comandos disponíveis
case "$1" in
    up)
        echo "--- Iniciando os serviços..."

        $COMPOSE_CMD up -d
        ;;
    down)
        echo "--- Parando e removendo os serviços..."
        $COMPOSE_CMD down
        ;;
    restart)
        echo "--- Reiniciando os serviços..."
        $COMPOSE_CMD down && $COMPOSE_CMD up -d
        ;;
    logs)
        echo "--- Exibindo logs dos serviços..."
        $COMPOSE_CMD logs -f
        ;;
    exec)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "ERRO: Uso correto: $0 {dev|prod} exec <serviço> <comando>"
            exit 1
        fi
        echo "--- Executando comando '$3' no serviço '$2'..."
        $COMPOSE_CMD exec "$2" "${@:3}"
        ;;
    ps)
        echo "--- Listando serviços em execução..."
        $COMPOSE_CMD ps
        ;;
    backup)
        CONTAINER_NAME="zammad-backup"

        echo "--- Criando backup do Zammad..."
        echo ">>> $COMPOSE_CMD exec $CONTAINER_NAME /opt/zammad/contrib/backup/zammad_backup.sh"
        $COMPOSE_CMD exec "$CONTAINER_NAME" "/opt/zammad/contrib/backup/zammad_backup.sh"

        # Criar o diretório de destino no host, se não existir
        echo ">>> mkdir -p $BACKUP_DEST_DIR"
        mkdir -p "$BACKUP_DEST_DIR"

        # Obtém os nomes dos arquivos de backup mais recentes
        LATEST_DB=$($COMPOSE_CMD exec "$CONTAINER_NAME" readlink -f "$BACKUP_DIR/latest_zammad_db.psql.gz")
        LATEST_FILES=$($COMPOSE_CMD exec "$CONTAINER_NAME" readlink -f "$BACKUP_DIR/latest_zammad_files.tar.gz")

        # Copia os backups mais recentes para o host
        echo "--- Copiando backups para $BACKUP_DEST_DIR..."
        echo ">>> $COMPOSE_CMD cp $CONTAINER_NAME:$LATEST_DB $BACKUP_DEST_DIR/latest_zammad_db.psql.gz"
        echo ">>> $COMPOSE_CMD cp $CONTAINER_NAME:$LATEST_FILES $BACKUP_DEST_DIR/latest_zammad_files.tar.gz"
        $COMPOSE_CMD cp "$CONTAINER_NAME:$LATEST_DB" "$BACKUP_DEST_DIR/latest_zammad_db.psql.gz"
        $COMPOSE_CMD cp "$CONTAINER_NAME:$LATEST_FILES" "$BACKUP_DEST_DIR/latest_zammad_files.tar.gz"

        ;;
    restore)
        echo "--- Restaurando backup do Zammad..."

        CONTAINER_NAME="zammad-backup"

        # Verifica se os arquivos de backup existem na pasta ./dump
        if [ ! -f "$BACKUP_DEST_DIR/latest_zammad_db.psql.gz" ] || [ ! -f "$BACKUP_DEST_DIR/latest_zammad_files.tar.gz" ]; then
            echo "ERRO: Nenhum backup encontrado em $BACKUP_DEST_DIR!"
            echo "Execute '$0 {dev|prod} backup' para gerar um novo backup antes de restaurar."
            exit 1
        fi

        # Copia os backups mais recentes para dentro do contêiner antes da restauração
        echo "--- Copiando backups para o contêiner..."
        echo ">>> $COMPOSE_CMD cp $BACKUP_DEST_DIR/latest_zammad_db.psql.gz $CONTAINER_NAME:$BACKUP_DIR/latest_zammad_db.psql.gz"
        echo ">>> $COMPOSE_CMD cp $BACKUP_DEST_DIR/latest_zammad_files.tar.gz $CONTAINER_NAME:$BACKUP_DIR/latest_zammad_files.tar.gz"

        $COMPOSE_CMD cp "$BACKUP_DEST_DIR/latest_zammad_db.psql.gz" "$CONTAINER_NAME:$BACKUP_DIR/latest_zammad_db.psql.gz"
        $COMPOSE_CMD cp "$BACKUP_DEST_DIR/latest_zammad_files.tar.gz" "$CONTAINER_NAME:$BACKUP_DIR/latest_zammad_files.tar.gz"

        # Obtém a data do backup a partir do nome do arquivo copiado
        BACKUP_DATE=$(basename "$BACKUP_DEST_DIR/latest_zammad_db.psql.gz" | grep -oE '[0-9]{14}')

#        if [ -z "$BACKUP_DATE" ]; then
#            echo "ERRO: Não foi possível determinar a data do backup!"
#            exit 1
#        fi

        # Executa a restauração dentro do contêiner
        echo "--- Iniciando restauração do backup..."
        echo ">>> $COMPOSE_CMD exec $CONTAINER_NAME /opt/zammad/contrib/backup/zammad_restore.sh latest"
        $COMPOSE_CMD exec "$CONTAINER_NAME" /opt/zammad/contrib/backup/zammad_restore.sh "latest"

        echo "Restauração concluída!"
        ;;
    copiar-backup)
        echo "📤 Copiando backup do contêiner para o host..."
        ./copiar-backup.sh
        ;;
    *)
        echo "--- Executando comando customizado: $COMPOSE_CMD $@"
        $COMPOSE_CMD "$@"
        ;;
esac