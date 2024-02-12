# SupportQuickActions
Application deployable via Jamf to allow front line support to use some routine commands without accessing the console.


- Current Variables to pass from Jamf Pro
     $4 - icon
     $5 - overlayicon
     $6 - bannerimage
	
- Current Supported Functions
	Computers
		Redeploy Jamf Framework, Lock Computer, Recovery Key, FileVault2 Key, LAPS Password
	Devices
		Clear Passcode, Wipe Device, Update Inventory