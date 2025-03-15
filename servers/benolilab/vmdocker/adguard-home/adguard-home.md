# Custom adguard commands and help
- stop the container
```
    docker stop adguardhome
```


- to modify the conf. AdGuardHome.yaml file:
```
	docker inspect adguardhome
```
- Locate the Volume Mount information for conf:
```
"Mounts": [
    {
        "Type": "bind",
        "Source": "/path/on/host",
        "Destination": "/path/in/container"
    }
]
```


- Access the Mounted Volume on the Host: Once you have the source path (e.g., /path/on/host), you can navigate to it using the cd command:
```
cd /path/on/host
```

- Open with editor (nano)
- Make changes as needed
- Restart the container
```
    docker start adguardhome
```