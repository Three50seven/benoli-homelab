Placeholder - this directory will be mounted to the selfsigned-certgen container for storing certs

# After New Certs Are Created:
For Windows just double click the crt file and add/Install it to the trusted certs.
Or optionally go through mmc (run > mmc > Add snapin for certs > import cert)

## Nginx Proxy Manager (NPM)
NPM stores its certs inside the container, so we’ll bind-mount the generated certs and import them manually.

- Recommended Folder:
Mount the certs like this in your NPM container (or docker compose yml):
```
-v /opt/mylab-certs:/mnt/certs
```
Then in NPM:

Go to SSL Certificates > Add SSL Certificate

Choose:

Custom SSL

Upload /mnt/certs/mylab.crt and /mnt/certs/mylab.key

Apply this certificate to your internal hostnames

NPM does not auto-reload custom certs — so when the script renews them, you may need to restart the NPM container or reapply the cert through the UI.

If you're auto-renewing the cert with your self-signed CA:

Mount the certs to /mnt/certs:ro (as you're doing).

Use NPM GUI to upload once as a Custom SSL cert.

When the cert renews (file is overwritten):

Optionally restart the NPM container to reload:

```
docker restart npm
```
Or re-select the cert in GUI if it’s not picked up automatically.

- Optional Auto-Renewal Hook
In your cert generation container:

```
# After renewal:
docker exec adguardhome kill -SIGHUP 1
docker restart npm_container
```

## Unbound Via OPNsense
Unbound doesn’t use TLS for its web interface but can serve DNS-over-TLS or DNS-over-HTTPS (DoH) if configured.

To serve DNS-over-TLS (DoT):
In OPNsense > Services > Unbound DNS > Advanced, add:

```
tls-cert-bundle: "/conf/mylab-rootCA.crt"
server-cert-file: "/conf/mylab.crt"
server-key-file: "/conf/mylab.key"
```
You’ll need to copy the certs to /conf or another persistent path.

Restart Unbound

You only need this if you want devices to query Unbound over encrypted DNS.

## AdGuard Home
Steps: 

Copy/mount the wildcard cert and key to AdGuard’s config directory:

```
cp mylab.crt /opt/adguardhome/certs/
cp mylab.key /opt/adguardhome/certs/
```
Update AdGuard config (usually AdGuardHome.yaml):

```
tls:
  enabled: true
  server_name: mylab.home
  certificate_chain: "/opt/adguardhome/certs/mylab.crt"
  private_key: "/opt/adguardhome/certs/mylab.key"
```
Restart AdGuard Home:

```
sudo systemctl restart AdGuardHome
```
