#!/bin/bash
export NEW_CONN_STRING=$(kubectl get secret -n $1 mm-postgres-connection --template={{.data.DB_CONNECTION_STRING}} | base64 -d - | sed -E "s#(postgres://mm_user:)(.+)(@)#\1$2\3#g" - | base64 -w 0 -)
kubectl patch secret -n $1 mm-postgres-connection --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/DB_CONNECTION_CHECK_URL\", \"value\":$NEW_CONN_STRING}]"
kubectl patch secret -n $1 mm-postgres-connection --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/DB_CONNECTION_STRING\", \"value\":$NEW_CONN_STRING}]"
kubectl patch secret -n $1 mm-postgres-connection --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/MM_SQLSETTINGS_DATASOURCEREPLICAS\", \"value\":$NEW_CONN_STRING}]"
export NEW_PW=$(echo -n $2 | base64 -w 0 -)
kubectl patch secret -n $1 mm-user.edgeless-mattermost-sql-cluster.credentials.postgresql.acid.zalan.do --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/password\", \"value\":$NEW_PW}]"
unset NEW_CONN_STRING
unset NEW_PW
