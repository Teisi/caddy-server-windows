# Super simple Caddy-Server files and config for windows only with GUI!
Config ready for Wordpress, Shopware, TYPO3.
Currently only tested on windows 10!
This script (GUI) seems to ned administrator rights for default ports 80(http) / 443(https) therefore windows will ask you for permission.

## Installation
Download [caddy server](https://caddyserver.com/download) and drop it in a location of your choice. \
Rename the downloaded caddy file (e. g. caddy_windows_amd64.exe) to "caddy.exe"! \
Then load the files of this repository into the same folder, the folder should then look like this:

- LocationOfYourChoice/caddy.exe \
- LocationOfYourChoice/Caddyfile \
- LocationOfYourChoice/server-manager/ \
- LocationOfYourChoice/start.gui.bat \
- etc. \

(optional) For PHP download the version(s) you want from [https://windows.php.net/download/](https://windows.php.net/download/).
Use the "Non Thread Safe" Versions for Windows! Don't forget to initialize / config the php.ini!
You can use multiple PHP versions at the same time.

(optional) For MySQL / MariaDB [download here](https://mariadb.org/download/?t=mariadb&p=mariadb&r=11.8.2&os=windows&cpu=x86_64&pkg=msi&mirror=archive).
You can use multiple MySQL / MariaDB versions at the same time (with different ports!).


## Usage
1. Configure the "Caddyfile" to your needs if you wish
2. Create your config for each of your projects within the "sites" directory (examples included)

### Manual start (mainly intended for debugging)
3. Start your PHP: `[absPathToPhp]/php-cgi.exe -b 127.0.0.1:9082` (9082 custom port, i use 82 for php version 8.2)
4. Start caddy: `cd [directory]/caddy run --config Caddyfile`

### GUI start
3. Configure your PHP paths in server-manager/config.json
4. Double-click on start.gui.bat \
   The first time you start with "auto https on" you will be asked by windows if you want to allow the caddy as local certificate authority.
5. enjoy :)

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
