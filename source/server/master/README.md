## Master server


Right now it has a very limited usefullnes but it does this:
	- Lets all gateway and world connect to itself (master server)
	- When a player connects to the gateway, the gateway can retrieve the list of available worlds via the server so it doesn't need to know all possible world adresses.
	- When a player try to access to a world server, the gateway will ask the master server to fetch him the available informations about the player on this server such as its characters.
	- Once the player choose its character on a specific server, a temporary token is generated allowing the client to connect to the target world server.
	- Act as the account data base, characters are stored in world servers.

I'am not sure right now what more it should do. 
