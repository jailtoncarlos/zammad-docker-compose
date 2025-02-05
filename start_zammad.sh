#!/bin/bash

# Verifica se um argumento foi passado
if [ -z "$1" ]; then
    echo "Uso: $0 [dev|prod]"
    exit 1
fi

# Define variáveis do ambiente
AMBIENTE=$1
REDE=""

if [ "$AMBIENTE" == "dev" ]; then
    REDE="zammad-network"
    COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose-dev.yml up -d"
    ACESSO="http://localhost:8080"
elif [ "$AMBIENTE" == "prod" ]; then
    REDE="proxy-network"
    COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
    ACESSO="https://seu-dominio.com"  # Substituir pelo domínio real
else
    echo "Opção inválida! Use 'dev' ou 'prod'."
    exit 1
fi

# Verifica se a rede existe, se não, cria
if ! docker network ls | grep -q "$REDE"; then
    echo "--- Criando rede $REDE..."
    echo ">>> docker network create $REDE"
    docker network create "$REDE"
    echo "Rede $REDE criada com sucesso!"
else
    echo "Rede $REDE já existe!"
fi

# Executa o comando Docker Compose apropriado
echo "--- Iniciando os serviços no ambiente $AMBIENTE..."
echo ">>> $COMPOSE_CMD"

if ! $COMPOSE_CMD; then
    echo "Erro ao iniciar os serviços!"
    exit 1
fi

# Aguarda o serviço zammad-nginx ficar pronto
echo "--- Aguardando o serviço 'zammad-nginx' iniciar..."
echo ">>> docker ps | grep -q \"zammad-nginx\""
while ! docker ps | grep -q "zammad-nginx"; do
    echo "Verificando novamente em 5 segundos..."
    sleep 5
done

# Exibe mensagem de sucesso e instruções finais
echo "O serviço 'zammad-nginx' está rodando!"
echo "O Zammad está disponível em: $ACESSO"
