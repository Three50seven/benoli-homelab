# Generate SSH Key pair for automated transfers
1. Generate an SSH Key Pair
Run the following command in your terminal:

```
	ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```
-t rsa: Specifies the RSA algorithm.
-b 4096: Uses a 4096-bit key for better security.
-C "your_email@example.com": Adds an optional comment (use your email for identification).

2. Save the Key
When prompted:

Enter file in which to save the key (/home/root/.ssh/id_rsa):
Press Enter to accept the default location (~/.ssh/id_rsa).
Or enter a custom path if you want to save it elsewhere.

3. Set a Passphrase (Optional)
You'll be asked:

Enter passphrase (empty for no passphrase):
Leave it empty if you don’t want to use a passphrase (useful for automated processes).
Enter a strong passphrase if you want added security.

4. Copy the Public Key to Your SSH Server
After generating the key pair, copy the public key (id_rsa.pub) to your remote server:
```
	ssh-copy-id user@<SERVER_IP>
```
Replace user@<SERVER_IP> with your actual SSH username and host.

Alternatively, manually copy the key:
```
	cat ~/.ssh/id_rsa.pub
```
Then, add it to the remote server’s ~/.ssh/authorized_keys file:
```
	echo "your-public-key-content" >> ~/.ssh/authorized_keys
	chmod 600 ~/.ssh/authorized_keys
```

5. Test SSH Connection
Verify that you can log in without a password:
```
	ssh -i ~/.ssh/id_rsa user@<SERVER_IP>
```

6. Rename the private key file to .ssh_private_key and move it to the docker secrets directory:
```
	cp ~/.ssh/id_rsa /opt/benolilab-docker/secrets/.ssh_private_key
```
