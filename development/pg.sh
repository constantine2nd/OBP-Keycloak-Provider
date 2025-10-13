#!/bin/bash

POSTGRES_CONTAINER_NAME=obp-keycloak-provider-postgres
docker stop $POSTGRES_CONTAINER_NAME
docker rm $POSTGRES_CONTAINER_NAME

# Run postgres
docker run -d --ulimit memlock=-1:-1 -it --rm=true --memory-swappiness=0 --name $POSTGRES_CONTAINER_NAME -e POSTGRES_USER=admin -e POSTGRES_PASSWORD=admin -e POSTGRES_DB=keycloak -p 5432:5432 postgres
