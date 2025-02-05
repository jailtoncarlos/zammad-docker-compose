#!/bin/bash

# Definição de variáveis para o usuário admin
ADMIN_USER="admin"
ADMIN_EMAIL="admin@meusite.com"
ADMIN_PASSWORD="SenhaForte123"

# Detecta automaticamente o contêiner correto do Rails Server
CONTAINER_NAME=$(docker ps --format "{{.Names}}" | grep "zammad-railsserver")

# Se não encontrar o contêiner, exibe erro e sai
if [ -z "$CONTAINER_NAME" ]; then
    echo "O contêiner do Zammad Rails Server não foi encontrado. Certifique-se de que o Zammad está rodando."
    echo "Sugestão: execute 'docker ps' para verificar os contêineres ativos."
    exit 1
fi

# Comando para criar um usuário admin no Zammad via Rails
echo "Criando conta administrativa no Zammad..."
docker exec -it "$CONTAINER_NAME" rails r "
  User.create!(
    login: '$ADMIN_USER',
    firstname: 'Admin',
    lastname: 'User',
    email: '$ADMIN_EMAIL',
    password: '$ADMIN_PASSWORD',
    password_confirmation: '$ADMIN_PASSWORD',
    role_ids: [1],
    active: true
  )
"

# Verifica se a conta foi criada com sucesso
if [ $? -eq 0 ]; then
    echo "Conta administrativa criada com sucesso!"
    echo "   Acesse o Zammad com:"
    echo "   Usuário: $ADMIN_EMAIL"
    echo "   Senha: $ADMIN_PASSWORD"
else
    echo "Erro ao criar a conta administrativa."
    exit 1
fi
