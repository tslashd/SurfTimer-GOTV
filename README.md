![Downloads](https://img.shields.io/github/downloads/tslashd/SurfTimer-GOTV/total?style=flat-square) ![Last commit](https://img.shields.io/github/last-commit/tslashd/SurfTimer-GOTV?style=flat-square) ![Open issues](https://img.shields.io/github/issues/tslashd/SurfTimer-GOTV?style=flat-square) ![Closed issues](https://img.shields.io/github/issues-closed/tslashd/SurfTimer-GOTV?style=flat-square) ![Size](https://img.shields.io/github/repo-size/tslashd/SurfTimer-GOTV?style=flat-square) 
# SurfTimer-GOTV

Keeps track of all runs made on the server and keeps demos for all **Runs**

***This plugin could generate a lot of data on your server, demo files are much bigger in size and time than SurfTimer .rec files***

### What the plugin does:
  - Starts recording a GOTV demo after a player has joined the server _(check cfg for path)_
  - Logs ALL finishes for the server _(check cfg for path)_
  - Logs ALL finishes for each map _(check cfg for path)_
  - No player left in the server
    - Saves demo _(check cfg for path)_ or **deletes the recorded demo if no map or bonus was completed**



### Config:
  - Use only characters which are allowed in filenames and folders
  - All configs paths start from ***serverfiles/csgo/***
  - All paths should be written without ***/*** at the end



### Requirements:
  - [SurfTimer](https://github.com/surftimer/Surftimer-Official) - should work on all versions but ***WRCPs*** will only be available for version 1.0.5 or newer
  - [SourceTV Manager](https://github.com/peace-maker/sourcetvmanager#sourcetv-manager) - tested on release 1.1
  - GOTV enabled on the server - tested without any delay on it
  - **databases.cfg** entry
  ```
  "demo_recorder"
	{
		"driver"    "mysql"
		"host"      "YOUR_HOST"
		"database"  "YOUR_DATABASE_NAME"
		"user"      "YOUR_USER"
		"pass"      "YOUR_PASSWORD"
	}
  ```



### What it would be nice to do:
 - [ ] Delete demos older than **X**
 - [ ] Disable text logs if convar is empty
 - [ ] Add option to lock **WR** demos section to a certain in-game flag
 - [ ] ....?
