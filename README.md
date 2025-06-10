# Super simple Caddy-Server files and config for windows only!
Currently only tested on windows 10!

## Installation
Download [caddy server](https://caddyserver.com/download) and drop it in a location of your choice. \
Then load the files of this repository into the same folder, the folder should then look like this:

- LocationOfYourChoice/caddy.exe \
- LocationOfYourChoice/Caddyfile \
- LocationOfYourChoice/server-manager/ \
- LocationOfYourChoice/start.gui.bat \
- etc.

## Usage
1. Configure the "Caddyfile" to your needs
2. Create your config for each of your projects within the "sites" directory (examples included)
3. Start your PHP: `[absPathToPhp]/php-cgi.exe -b 127.0.0.1:9082` (9082 custom port, i use 82 for php version 8.2)
4. Start caddy: `cd [directory]/caddy run --config Caddyfile`

### (optional) if you wish to start caddy and php via GUI
1. Configure your PHP paths in server-manager/config.json
2. Double-click on start.gui.bat
3. enjoy :)

#### Problems
#### https not working?
Check if port 443 is used (for 0.0.0.0:443, should not be listet there)
`netstat -ano | findstr :443`

if 0.0.0.0:443 is listed, try:
`net stop http`

Mostly this is caused by the service "Remote ... RAS" | "Routing and RAS".
You can use caddy without https (see Caddyfile -> disable local_certs and enable auto_https off)
OR set this service to "manual",
to do this -> windows taskbar search for "service" (system) and there search for "Routing and RAS" -> right-click -> stop AND right-click -> settings -> "Starttype" set to manual.
