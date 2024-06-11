![Downloads](https://img.shields.io/github/downloads/tslashd/SurfTimer-GOTV/total?style=flat-square) ![Last commit](https://img.shields.io/github/last-commit/tslashd/SurfTimer-GOTV?style=flat-square) ![Open issues](https://img.shields.io/github/issues/tslashd/SurfTimer-GOTV?style=flat-square) ![Closed issues](https://img.shields.io/github/issues-closed/tslashd/SurfTimer-GOTV?style=flat-square) ![Size](https://img.shields.io/github/repo-size/tslashd/SurfTimer-GOTV?style=flat-square) 
# SurfTimer-GOTV

Keeps track of all runs made on the server and keeps demos for all **Runs**

***This plugin could generate a lot of data on your server, demo files are much bigger in size and time than SurfTimer .rec files***

### What the plugin does:
  - Starts recording a GOTV demo after a player has joined the server _(check cfg for path)_
  - Logs ALL finishes for the server _(check cfg for path)_
  - Logs ALL finishes for each map _(check cfg for path)_
  - No player left in the server
    - Saves demo _(check cfg for path)_ or **deletes the recorded demo if no map, bonus or stage was completed**
  - Using the `!demos` command will show a menu from which you can find demos for all runs currently stored in the database (also lists all of them in the player console)
    - Selecting a demo from the menu will call the `SurfTV_SelectedDemo` forward which you can use in conjuction with another plugin to move demos around to publicly accessible folders for players to download them
    - Without utilizing the forward nothing will basically happen without some edit to the code and compiling again or making another plugin (check out [this](https://github.com/tslashd/SurfTimer-GOTV?tab=readme-ov-file#some-additional-information) paragraph)
    


### Config:
  - **Automatically created when the plugin loads, should be edited**
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



### Some additional information:
Out of the box this plugin will **NOT** move any files to a predefined folder where people can download them. You will have to either make your `sm_ck_gotv_demopath` be accessible with a web server and set the `sm_ck_gotv_downloadurl` to the url of said folder, or make a separate plugin utilizing the `SurfTV_SelectedDemo` forward to move demo files to a folder which is already accessible publicly through a domain or IP address and set that to be the `sm_ck_gotv_downloadurl`.
The idea behind this plugin was to automate demo recordings using [SVR](https://github.com/crashfort/SourceDemoRender) all the data for each run that is being stored in the database by this plugin is sufficient enough to create [VDM](https://developer.valvesoftware.com/wiki/Demo_Recording_Tools) files for each run which can display for instance checkpoint comparisons during the recording at the exact time the checkpoint was reached which eliminates the need for further video editing after a run has been recorded. I have decided not to include that in this plugin as it would have become a bit overwhelming in my opinion.
- Easiest way to display a chat message with the link for download (assuming that you have made the demo saving folder accessible on your domain) is to add `CPrintToChat` below [this line](https://github.com/tslashd/SurfTimer-GOTV/blob/main/addons/sourcemod/scripting/SurfTimer-GOTV.sp#L668).
- Another way of doing it with a separate plugin would be something like this:
```sp
public void SurfTV_SelectedDemo(int client, const char[] demoRunTime, int demoStart, int demoEnd, const char[] demoName, const char[] dlUrl, const char[] demoPlayer, const char[] demoFdl)
{
	// Here you can move your demo file around to a different folder from where players can download the file if your demo recording folder is not publicly accessible

	CPrintToChat(client, "{blue}[Demos]{default} Selected demo run time {gold}%s{default}. Link:", demoRunTime);
	CPrintToChat(client, "{blue}[Demos]{default} {yellow}%s/%s.dem", dlUrl, demoName); // Forward slash should be removed if your downloadurl convar ends with it
	CPrintToChat(client, "{blue}[Demos]{default} Start: {yellow}%i{default} | End: {yellow}%i{default} | PlayerID: {yellow}%s", demoStart, demoEnd, demoPlayer);

	return;
}
```
Pull requests are definitely welcome and I will happily approve them for improving this plugin, but I do not really see this happening with the current state of Surf and the community as a whole.
# _**Have fun sliding those triangles!**_ 🏄



### What it would be nice to do:
 - [ ] Delete demos older than **X**
 - [x] Disable text logs if convar is empty
 - [x] Add option to lock **WR** demos section to a certain in-game flag
 - [x] Make an include file
 - [ ] Improve the way demo data is sent to menu (splitting is possibly not the most optimal way)
 - [ ] ....?
