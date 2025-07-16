# Note: This is a manual process that has been replaced with NPM, a duckdns domain, and auto-site-cert-renewal
# Also, see "issue-wildcard-cert.sh" as an exmaple to partially automate the site-cert creation.
# Generate Self-signed SSL Site Cert for HTTPS Use in Nginx Proxy Manager (NPM)
Pre Setup:
Make a new site-certs directory:
```
mkdir /opt/site-certs

cd /opt/site-certs

# Optional - didn't use this, but to gerate a quick cert without an "authority" do this:
openssl req -x509 -nodes -days 731 -newkey rsa:4096 -keyout wildcard.mylab.local.key -out wildcard.mylab.local.crt -subj "/CN=*.mylab.local"
```

1. Generate a Certificate Authority (CA)
```
# Generate root key
openssl genrsa -out mylab-rootCA.key 4096

# Generate root cert, NOTE: 1825=5yrs
openssl req -x509 -new -nodes -key mylab-rootCA.key -sha256 -days 1825 -out mylab-rootCA.crt -subj "/C=US/ST=StateName/L=CityName/O=OrgName/CN=OrgName Root CA"
```

2. Create the Wildcard Cert CSR + Key
```
openssl genrsa -out mylab-wildcard.key 4096

openssl req -new -key mylab-wildcard.key -out mylab-wildcard.csr  -subj "/C=US/ST=StateName/L=CityName/O=OrgName/CN=*.mylab.local"
```

| Field | Description                          | Example Value        | Notes                                            |
|-------|--------------------------------------|----------------------|--------------------------------------------------|
| `C`   | Country Code                         | `US`                 | Two-letter country code                          |
| `ST`  | State or Province                    | `StateName`          | Can be any region name you like                  |
| `L`   | Locality (typically city)            | `CityName`			  | Used to indicate city or local area              |
| `O`   | Organization Name                    | `OrgName`            | Your homelab name or org name                    |
| `CN`  | Common Name (FQDN for the cert)      | `*.mylab.local`      | Must match the domain you're securing            |


3. Create a Config File for Extensions (e.g., extfile.cnf)
```
cat <<EOF > extfile.cnf
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = *.mylab.local
DNS.2 = mylab.local
EOF
```

4. Sign the Wildcard Cert Using Your Root CA
**Note: 731=2 years and a day, most browsers will support max of 825 days**
```
openssl x509 -req -in mylab-wildcard.csr -CA mylab-rootCA.crt -CAkey mylab-rootCA.key -CAcreateserial -out mylab-wildcard.crt -days 731 -sha256 -extfile extfile.cnf

# To view details about the cert, use the following:
openssl x509 -in mylab-wildcard.crt -text -noout

# If you want to inspect a DER-encoded cert (common in .cer files), use:
openssl x509 -in mylab-wildcard.cer -inform der -text -noout
```

5. Upload to Nginx Proxy Manager (NPM)
In NPM:
- Go to SSL Certificates -> Add Custom Certificate
- Upload:
- Certificate: mylab-wildcard.crt
- Key: mylab-wildcard.key

6. Trust the Root CA on All Devices
- Import mylab-rootCA.crt into:
- Windows: certmgr.msc -> Trusted Root Certification Authorities
- macOS: Keychain Access -> System -> Trust Always
- Linux: Copy to /usr/local/share/ca-certificates/, then run sudo update-ca-certificates
- Mobile Devices: Usually in Wi-Fi or security settings
	- For example, on Android, Open Settings > Security & privacy > More security settings > Encryption & Credentials
	- Tap Install a certificate > CA certificate
	- Choose the location where you saved the file (e.g. Downloads)
	- Select the crt file
	- Give it a name and confirm
	- You will most likely have to enter your Android's unlock code/patter/pw to install the trusted credentials

7. Add the Host override in OPNsense and DNS Rewrite in AdGuard
- OPNsense: Services > Unbound > Overrides > + to add new > {Enter * as Host Name, Domain, IP of NPM etc. and click "Save"} > Apply
- AdGuard: Filters > DNS Rewrites {Enter Domain and IP}
**Note: It's easiest to just add a wildcard DNS Rewrite in AdGuard (e.g. *.mylab.local) and add the NPM IP instead of individual entries.**
