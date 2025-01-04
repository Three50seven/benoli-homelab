Used draw.io > app.diagrams.net to build topology.
https://app.diagrams.net/

saved as HTML

Considerations for subnet:
https://www.reddit.com/r/homelab/comments/pkv9nk/trying_to_use_1921682x_but_wont_work/
Change your subnet mask on your internet router from 192.168.1.1/24 to 192.168.1.1/22. 
This will allow you to have 1024 Ip addresses. Your subnet will go from 192.168.0.1 - 192.168.3.254. 
Keep your existing DHCP scope in the 192.168.1.10-254 (or whatever it is). Your dynamically 
allocated addresses will fall in that range, and everything can still use 192.168.1.1 as the gateway. 
You will also have addresses available in the 192.168.0, 192.168.2, and 192.168.3 ranges. 
They will all be in the same subnet, which means the same layer 2 VLAN. 
