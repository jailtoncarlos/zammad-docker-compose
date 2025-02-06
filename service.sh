#!/bin/bash

function verificar_criar_rede() {
    environment=$1

    if [ "$environment" == "dev" ]; then
        rede="zammad-network"
    elif [ "$environment" == "prod" ]; then
        rede="proxy-network"
    fi

    # Verifica se a rede foi informada
    if [ -z "$rede" ]; then
        echo "ERRO: Nenhuma rede foi informada para a função verificar_criar_rede()"
        return 1
    fi

    # Verifica se a rede existe, se não, cria
    if ! docker network ls | grep -q "$rede"; then
        echo "--- Criando rede $rede..."
        echo ">>> docker network create $rede"
        docker network create "$rede"

        if [ $? -eq 0 ]; then
            echo "Rede $rede criada com sucesso!"
        else
            echo "ERRO: Falha ao criar a rede $rede"
            return 1
        fi
    else
        echo "Rede $rede já existe!"
    fi
}

function aguarda_servico_ficar_pronto() {
    container_name="$1"

    # Aguarda o serviço zammad-nginx ficar pronto
    echo "--- Aguardando o serviço '$container_name' iniciar..."
    echo ">>> docker ps | grep -q \"$container_name\""
    while ! docker compose ps | grep -q "$container_name"; do
        echo "Verificando novamente em 5 segundos..."
        sleep 5
    done
    echo "Container $container_name está rodando!"
}

function inicializar_servicos() {
    environment=$1
    command=$2
    args="${@:3}" # Todos os argumentos após o segundo

    verificar_criar_rede "$environment"

    if [ "$command" == "up" ]; then
        echo "--- Iniciando os serviços..."
        $COMPOSE_CMD up -d $args
    elif [ "$command" == "restart" ]; then
        echo "--- Reiniciando os serviços..."
        $COMPOSE_CMD down && $COMPOSE_CMD up -d $args
    else
        echo "ERRO: Opção inválida! Use 'up' ou 'restart'."
        exit 1
    fi

    aguarda_servico_ficar_pronto "zammad-nginx"
}

# Exemplo de uso da função:
# verificar_criar_rede "zammad-network"


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

case "$ENVIRONMENT" in
    dev)
        COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose-dev.yml"
        echo "Usando ambiente de **desenvolvimento** (docker-compose-dev.yml)"
        ACESSO="http://localhost:8080"
        ;;
    prod)
        COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose-prod.yml"
        echo "Usando ambiente de **produção** (docker-compose-prod.yml)"
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
        inicializar_servicos "$ENVIRONMENT" "up" "${@:2}"
        ;;
    down)
        echo "--- Parando e removendo os serviços..."
        $COMPOSE_CMD down
        ;;
    restart)
        inicializar_servicos "$ENVIRONMENT" "restart" "${@:2}"
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

        aguarda_servico_ficar_pronto "$CONTAINER_NAME"

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
        CONTAINER_NAME="zammad-backup"

        echo "--- Parando todos os serviços..."
        $COMPOSE_CMD down

        echo "--- Inicializando os serviços do banco e do backup ..."
        $COMPOSE_CMD up $CONTAINER_NAME -d

        aguarda_servico_ficar_pronto "$CONTAINER_NAME"

        echo "--- Restaurando backup do Zammad..."

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


        # Executa a restauração dentro do contêiner
        echo "--- Iniciando restauração do backup..."
        echo ">>> $COMPOSE_CMD exec $CONTAINER_NAME /opt/zammad/contrib/backup/zammad_restore.sh latest"
        $COMPOSE_CMD exec "$CONTAINER_NAME" /opt/zammad/contrib/backup/zammad_restore.sh "latest"

        echo "Restauração concluída!"

        pause "Pressione qualquer tecla para continuar e inicializar todos os containers ..."
        inicializar_servicos "$ENVIRONMENT" "up"

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

echo "O Zammad está disponível em: $ACESSO"
echo "Usuário: admin"
echo "senha: SenhaForte123"