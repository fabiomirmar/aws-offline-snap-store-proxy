# aws-offline-snap-store-proxy
Deploy RDS PostgresSQL db, an instance with snap-store proxy in airgapped mode and a client

Setup the variables in config.sh and then create the AWS resources with:

```
./create_resources.sh
```

When ready, deploy the "registration" VM (the one with Internet access that will be used to download the snap-store snap

```
./setup_snap_registration.sh
```

When ready, deploy the snap-proxy VM

```
./setup_snap_proxy.sh
```

And ready, test a client:

```
./setup_snap_client.sh
```
