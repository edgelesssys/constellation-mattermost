# General

This repo holds the necessary helm charts to deploy the [Zalando Postgres operator](https://github.com/zalando/postgres-operator), [MinIO operator](https://operator.min.io/) and [Mattermost operator](https://docs.mattermost.com/install/install-kubernetes.html).
Other tools that are installed are cert-manager, external-dns and nginx-ingress.

`mm-infra` is the helm chart that should be deployed once per cluster.
It includes the operators.
Since some of the resources depend on each other or should be deployed to their own namespace for easier management, they are installed separate.
See section "Deployment" below.

`mm-app` is the helm chart that is deployed once per environment.
Currently two environments, `staging` and `prod`, are planned.
The environment includes a postgres cluster, a minio tenant and the mattermost app.
The postgres cluster is backed up once per day to a backup-tenant that lives in it's own namespace and is deployed as part of `mm-infra`.

Whenever you see paths or env variables that reference `s3` - they don't point to AWS.
Instead, they point to the cluster-internal MinIO tenants.

# Pipeline secrets

The workflows that interact with the cluster rely on a GitHub Actions secret called `KUBEADM_CONF`.
This secret holds the kubeconfig encoded in base64.
If you setup a new cluster you will need to update this secret.
Command for base64 encoding: `cat constellation-admin.conf | base64 -w 0 > admin.b64`.

# Deployment
There are GitHub Actions workflows to deploy/test changes.
In case you change something in the helm charts, like the version, you would deploy the changes to the `staging` env first, test if everything is fine and then deploy to `prod`.
If you need to run specific steps manually, the workflows can be used as reference.
# Backups
Run the `Restore SQL backup` action.
This will restore a backup from the `psql-backups` bucket in the MinIO tenant of the selected env.
The backup is restored by deleting the current postgres-cluster in the env and creating a new postgres-cluster based on the selected backup.
The timestamp field is used to select the backup that will be restored.
The postgresql-operator will restore the latest backup before the timestamp that is entered.
So in case you want the latest backup and you don't know when the last backup was executed, select a timestamp that is slightly into the future.

After restoring a backup, the postgresql-operator might take up to 10 minutes until it updates the pods/statefulset/... based on the new `postgresql` resource that is created as a result of the action.

After the new cluster is running, the password of the DB user `mm_user` has to be updated.
In your local shell:
- Set env: `export MM_ENV=staging && export KUBECONFIG=...`
- Get the current `postgres` user pw: `export POSTGRES_PW=$(kubectl get secret -n $MM_ENV postgres.edgeless-mattermost-sql-cluster.credentials.postgresql.acid.zalan.do --template={{.data.password}} | base64 -d -)`
- `echo $POSTGRES_PW`
- Start a postgres container in the cluster: `kubectl run testpsql -n $MM_ENV --image=postgres -i --rm --tty --command -- sh`
  - (Inside container container shell..)
  - Set DB connection string: `export CONN=postgres://postgres:<paste value of POSTGRES_PW here>@edgeless-mattermost-sql-cluster:5432/mattermost_main`
  - `psql --dbname=$CONN -c "select value from configurations where active;"`
  - You should see a JSON file, scroll until you see `SqlSettings.DataSource`. Copy the password from that connection string. Let us call it NEW_DB_PW.
  - Update user password: `psql --dbname=$CONN -c "ALTER USER mm_user WITH PASSWORD '<paste NEW_DB_PW>';"`
  - Close container shell
- Update k8s secrets: `bash set_db_secret.sh $MM_ENV <paste NEW_DB_PW>`
- Delete mattermost pod so it will be restarted.

**Important:** You might encounter cases in which Mattermost is still not able to connect to the DB.
In those cases you might have to modify the connection string that is saved in the `configurations` table.
For some reason Mattermost uses this string for connecting to the DB after it connected successfully once with the env variable that is backed by the `mm-postgres-connection` secret.

# Misc / Known Errors
- The postgres-operator docs state that you [should not](https://postgres-operator.readthedocs.io/en/latest/administrator/#logical-backups) rely on logical backups.
- The "Test Live URL" Button in the staging environment does not work because the TLS certificate is not trusted.
