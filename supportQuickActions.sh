#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
##############################################################################
#####                       Support Quick Actions                        #####
#####                                                                    #####
##### Collection of tools for support techs to diagnose devices on-site  #####
#####                                                                    #####
#####                                                                    #####
##############################################################################
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 


# # # # # # # # # # # # # # # # # # # # # #
# Declare varibles to be passed/refrence  #
# # # # # # # # # # # # # # # # # # # # # #

#apiUser=""
#apiPassword=""
#jamfProURL=""
#SERIAL=""
wipe_lock_passcode="123456"
icon=${4:-"info"}
overlayicon=${5:-"sf=square.and.arrow.down"}
bannerimage=${6:-"https://github.com/gilmoreag2009/SupportQuickActions/blob/main/bg.png?raw=true"}
#token -> bearerToken
#computerID -> computerManagementID
#deviceID -> deviceManagementID
scriptLog="/private/var/tmp/quickActions.log"
swiftDialogMinimumRequiredVersion="2.4.0"


# # # # # # # # # # # # # # # # # # # # # # # #
# Define functions for commomly used commands # 
# # # # # # # # # # # # # # # # # # # # # # # #

#### Dialog related functions ####



updateScriptLog() {
	echo -e "$( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

dialogInstall() {
	
	# Get the URL of the latest PKG From the Dialog GitHub repo
	dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	
	# Expected Team ID of the downloaded PKG
	expectedDialogTeamID="PWA5E9TQ59"
	
	updateScriptLog "PRE-FLIGHT CHECK: Installing swiftDialog..."
	
	# Create temporary working directory
	workDirectory=$( /usr/bin/basename "$0" )
	tempDirectory=$( /usr/bin/mktemp -d "/private/tmp/$workDirectory.XXXXXX" )
	
	# Download the installer package
	/usr/bin/curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"
	
	# Verify the download
	teamID=$(/usr/sbin/spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
	
	# Install the package if Team ID validates
	if [[ "$expectedDialogTeamID" == "$teamID" ]]; then
		
		/usr/sbin/installer -pkg "$tempDirectory/Dialog.pkg" -target /
		sleep 2
		dialogVersion=$( /usr/local/bin/dialog --version )
		updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version ${dialogVersion} installed; proceeding..."
		
	else
		
		# Display a so-called "simple" dialog if Team ID fails to validate
		osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "Setup Your Mac: Error" buttons {"Close"} with icon caution'
		completionActionOption="Quit"
		exitCode="1"
		quitScript
		
	fi
	
	# Remove the temporary working directory when done
	/bin/rm -Rf "$tempDirectory"
	
}

dialogCheck() {
	
	if [[ ! -f "${scriptLog}" ]]; then
		touch "${scriptLog}"
	fi
	# Output Line Number in `verbose` Debug Mode
	if [[ "${debugMode}" == "verbose" ]]; then updateScriptLog "PRE-FLIGHT CHECK: # # # SETUP YOUR MAC VERBOSE DEBUG MODE: Line No. ${LINENO} # # #" ; fi
	
	# Check for Dialog and install if not found
	if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ]; then
		
		updateScriptLog "PRE-FLIGHT CHECK: swiftDialog not found. Installing..."
		dialogInstall
		
	else
		
		dialogVersion=$(/usr/local/bin/dialog --version)
		if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
			
			updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating..."
			dialogInstall
			
		else
			
			updateScriptLog "PRE-FLIGHT CHECK: swiftDialog version ${dialogVersion} found; proceeding..."
			
		fi
		
	fi
	
}

dialogCheck


#### Functions for dealing with response from Jamf - JSON value extration and error handling ####

# Function to extract value from JSON using awk - Arguments: JSON input, key to extract.
extract_from_json() {
	echo "$1" | awk -v key="$2" '
		BEGIN {
			RS = "[},]";
			FS = "[:,]";
		}
		{
			for (i = 1; i <= NF; i += 2) {
				if ($i ~ "\"" key "\"") {
					gsub(/["{}]/, "", $(i + 1));
					gsub(/^[\t ]+|[\t ]+$/, "", $(i + 1));
					print $(i + 1);
					exit;
				}
			}
		}
	'
}

# Displays results from checks - pass two variables.
display_result() {
	/usr/local/bin/dialog \
	--bannertitle "Support Quick Actions" \
	--message "$message:  $result" \
	--bannerimage $bannerimage \
	--titlefont "size=26,shadow=1" \
	--messagefont size=14 \
	--height 400 \
	--width 600 \
	--iconsize 120  \
	--ontop \
	--moveable \
	--position center \
	--quitkey g \
	--button1text "Close" \
	--icon $icon \
	--overlayicon $overlayicon \
	--position center
	updateScriptLog "Result Displayed - $message:  $result"
}

display_laps() {
	/usr/local/bin/dialog \
	--bannertitle "Support Quick Actions" \
	--message "Username:  $laps_username<br>Password: $laps_password" \
	--bannerimage $bannerimage \
	--titlefont "size=26,shadow=1" \
	--messagefont size=14 \
	--height 400 \
	--width 600 \
	--iconsize 120  \
	--ontop \
	--moveable \
	--position center \
	--quitkey g \
	--button1text "Close" \
	--icon $icon \
	--overlayicon $overlayicon
	--position center
	updateScriptLog "Result Displayed - Username:  $laps_username"
}

# Checks results from bearer token - pass result from token commands.
check_token() {
	if [ -z "$1" ]; then
		message="Incorrect URL"
		result="Check domain or enter without https://"
	elif [[ $1 == *"Bad Request"* || $1 == *"httpStatus"* || $1 == *"Access Denied"* || $1 == *"Status page"* ]]; then
		message="Incorrect Username/Password"
		result="Failure"
	else
		result="Token Good"
	fi
}

# Checks results from computer/device ID curl command - pass result from ID commands.
check_serial() {
	updateScriptLog  "Checking Serial"
	if [[ $1 == *"<mobile_device>"* || $1 == *"<computer>"*  ]]; then
		updateScriptLog  "Success: Device Found"
	else
		result="Failure"
	fi
}

# Checks results from various commands - pass result from commands.
check_status() {
	if [[ $1 == *"Bad Request"* || $1 == *"httpStatus"* || $1 == *"Access Denied"* || $1 == *"Status page"* ]]; then
		result="Failure"
	else
		result="Command Sent"
	fi
}


#### Token Related Functions ###

# Gets Bearer Token from Jamf Pro, checks results then saves as bearerToken variable.
bearer_token() {
	token=$( /usr/bin/curl \
	--request POST \
	--silent \
	--url "$jamfProURL/api/v1/auth/token" \
	--user "$apiUser:$apiPassword" )
	check_token "$token"
	if [[ "$result" == "Failure" || "$result" == "Check domain or enter without https://" ]]; then
		display_result
		exit 0
	else
		bearerToken=$( /usr/bin/plutil -extract token raw - <<< "$token" )
		updateScriptLog "Bearer Token Check Successful"
	fi
}

# Expires Bearer Token
expire_token() {
	# Expire auth token
	/usr/bin/curl \
	--header "Authorization: Bearer $bearerToken" \
	--request POST \
	--silent \
	--url "$jamfProURL/api/v1/auth/invalidate-token"
	updateScriptLog "Token Expired"
}

#### Computer Related Functions  ####

# Gets Computer ID from Jamf Pro, checks results then saves as computerID variable.
computer_instance_ID() {
	response=$(curl -s -X GET \
	-H "Authorization: Bearer $bearerToken" \
	-H "Accept: application/xml" \
	"$jamfProURL/JSSResource/computers/serialnumber/$SERIAL")
	check_serial "$response"
	if [[ "$result" == "Failure" ]]; then
		message="Serial $SERIAL not found on $jamfProURL"
		display_result
		exit 0
	else
		# Extract the computer ID based on the serial number from the response using xmllint and sed
		computerID=$(echo "$response" | xmllint --xpath 'string(/computer/general/id)' - | sed 's/[^0-9]*//g')
		updateScriptLog "Computer Instance ID : $computerID"
	fi
}

# Retreives Computer Management ID using Computer ID
computer_management_ID() { 
	# Send API request to get the computer inventory details
	response=$(curl -s -X GET \
		-H "Authorization: Bearer $bearerToken" \
		-H "accept: application/json" \
		"$jamfProURL/api/v1/computers-inventory-detail/$computerID")
	
	# Extract the management ID from the response using awk
	computerManagementID=$(echo $response | grep -o '"managementId" : "[^"]*' | cut -d '"' -f 4)
	updateScriptLog "Computer Management ID: $computerManagementID"
}

redeploy_framework() {
	redeployresult=$(/usr/bin/curl \
	--header "Authorization: Bearer $bearerToken" \
	--request POST \
	--url "$jamfProURL/api/v1/jamf-management-framework/redeploy/$computerID")
	check_status "$redeployresult"
	message="Redeploy Framework"
	display_result
}

filevault_recovery_key() {
	fvresponse=$(curl --request GET \
	--header "Authorization: Bearer $bearerToken" \
	--url $jamfProURL/api/v1/computers-inventory/$computerID/filevault \
	--header 'accept: application/json')
	result=$(echo $fvresponse | grep -o '"personalRecoveryKey" : "[^"]*' | cut -d '"' -f 4)
	message="FileVault2 Key"
	display_result
}

recovery_lock_password() {
	rlresponse=$(curl --request GET \
	--header "Authorization: Bearer $bearerToken" \
	--url $jamfProURL/api/v1/computers-inventory/$computerID/view-recovery-lock-password \
	--header 'accept: application/json')
	result=$(echo $rlresponse | grep -o '"recoveryLockPassword" : "[^"]*' | cut -d '"' -f 4)
	message="Recovery Lock Password"
	display_result
}

lock_computer() {
	lockresponse=$(curl --request POST \
	--header "Authorization: Bearer $bearerToken" \
	--request POST \
	--url $jamfProURL/JSSResource/computercommands/command/DeviceLock/passcode/$wipe_lock_passcode/id/$computerID)
	check_status "$lockresponse"
	message="Computer Lock"
	display_result
}

JamfLaps() {
	
	# Send API request to get the LAPS username
	laps_username_response=$(curl -s -X GET \
	-H "Authorization: Bearer $bearerToken" \
	-H "accept: application/json" \
	"$jamfProURL/api/v2/local-admin-password/$computerManagementID/accounts")
	
	# Extract the LAPS username from the response using awk
	laps_username=$(extract_from_json "$laps_username_response" "username")
	
	updateScriptLog "LAPS Username: $laps_username"
	
	# Send API request to get the LAPS password
	laps_password_response=$(curl -s -X GET \
	-H "Authorization: Bearer $bearerToken" \
	-H "accept: application/json" \
	"$jamfProURL/api/v2/local-admin-password/$computerManagementID/account/$laps_username/password")
	
	# Extract the LAPS password from the response using awk
	laps_password=$(extract_from_json "$laps_password_response" "password")
	
	display_laps
}

#### Device Related Functions ####

# Gets Device ID from Jamf Pro, checks results then saves as deviceID variable.
device_instance_ID() {
	dresponse=$(curl -s -X GET \
	-H "Authorization: Bearer $bearerToken" \
	-H "Accept: application/xml" \
	"$jamfProURL/JSSResource/mobiledevices/serialnumber/$SERIAL")
	check_serial "$dresponse"
	if [[ "$result" == "Failure" ]]; then
		message="Serial $SERIAL not found on $jamfProURL"
		display_result
		exit 0
	else
		# Extract the computer ID based on the serial number from the response using xmllint and sed
		deviceID=$(echo "$dresponse" | xmllint --xpath 'string(/mobile_device/general/id)' - | sed 's/[^0-9]*//g')
		updateScriptLog "Device ID: $deviceID"
	fi
}

# Retreives Device Management ID using Device ID
device_management_ID() {
	# Send API request to get the computer inventory details
	dresponse2=$(curl -s -X GET \
		-H "Authorization: Bearer $bearerToken" \
		-H "accept: application/json" \
		"$jamfProURL/api/v2/mobile-devices/$deviceID")
	
	# Extract the management ID from the response using awk
	deviceManagementID=$(echo $dresponse2 | grep -o '"managementId" : "[^"]*' | cut -d '"' -f 4)
	updateScriptLog "Device ID: $deviceManagementID"
	
}

wipe_device() {
	wiperesponse=$(curl --request POST \
	-H "Authorization: Bearer $bearerToken" \
	-H "accept: application/json" \
	--url $jamfProURL/JSSResource/mobiledevicecommands/command/EraseDevice/id/$deviceID)
	check_status "$wiperesponse"
	message="Wipe Device"
	display_result 
}

clear_Passcode() {
	clearresponse=$(curl --request POST \
	-H "Authorization: Bearer $bearerToken" \
	-H "accept: application/json" \
	--url $jamfProURL/JSSResource/mobiledevicecommands/command/ClearPasscode/id/$deviceID)
	check_status "$clearresponse"
	message="Clear Passcode"
	display_result 
}

update_device_inventory() {
	inentoryresponse=$(curl --request POST \
	--url $jamfProURL/JSSResource/mobiledevicecommands/command/UpdateInventory/id/$deviceID)
	check_status "$clearresponse"
	message="Update Inventory"
	display_result
}

###################################
##### Script Body Starts Here #####
###################################

answer=$(/usr/local/bin/dialog \
--bannertitle "Support Quick Actions" \
--message "" \
--textfield "Username",required \
--textfield "Password",required,secure \
--textfield "URL",required \
--textfield "Serial",required \
--selecttitle "Computer or Mobile Device",required \
--selectvalues "Computer, Mobile Device" \
--bannerimage $bannerimage \
--titlefont "size=26,shadow=1" \
--messagefont size=14 \
--height 400 \
--width 600 \
--iconsize 120  \
--ontop \
--moveable \
--position center \
--quitkey g \
--button1text "OK" \
--icon $icon \
--overlayicon $overlayicon \
--position center)

formatted_answer=$(echo "$answer" | sed 's/:/: /g' | sed 's/"//g')

apiUser=$(echo "$formatted_answer" | grep "Username : [^ ]*" | awk '{print $3}')
apiPassword=$(echo "$formatted_answer" | grep "Password : [^ ]*" | awk '{print $3}')
jamfProDomain=$(echo "$formatted_answer" | grep "URL : [^ ]*" | awk '{print $3}')
SERIAL=$(echo "$formatted_answer" | grep "Serial : [^ ]*" | awk '{print $3}')
device_or_computer=$(echo "$formatted_answer" | grep "SelectedOption : [^ ]*" | awk '{print $3}')
jamfProURL="https://$jamfProDomain"
bearer_token

if [ $device_or_computer == 'Computer' ] 
then
	computer_instance_ID
	answer=$(/usr/local/bin/dialog \
	--bannertitle "Support Quick Actions" \
	--message "  " \
	--selecttitle "Computer Functions",required \
	--selectvalues "Redeploy Jamf Framework, Lock Computer, Recovery Key, FileVault2 Key, LAPS Password" \
	--bannerimage $bannerimage \
	--titlefont "size=26,shadow=1" \
	--messagefont size=14 \
	--height 400 \
	--width 600 \
	--iconsize 120  \
	--ontop \
	--moveable \
	--position center \
	--quitkey g \
	--button1text "OK" \
	--icon $icon \
	--overlayicon $overlayicon \
	--position center)
	
	formatted_answer=$(echo "$answer" | sed 's/:/: /g' | sed 's/"//g')
	function=$(echo "$formatted_answer" | grep "SelectedOption : [^ ]*" | awk '{print $3}')
	
	if [ $function == 'Redeploy' ] 
	then
		redeploy_framework
		expire_token
	elif [ $function == 'Lock' ]
	then
		lock_computer
		expire_token
	elif [ $function == 'Recovery' ]
	then
		recovery_lock_password
		expire_token
	elif [ $function == 'FileVault2' ]
	then
		filevault_recovery_key
		expire_token
	elif [ $function == 'LAPS' ]
	then
		computer_management_ID
		JamfLaps
		expire_token
	else
		echo "Error"
	fi
	
else
	device_instance_ID
	answer=$(/usr/local/bin/dialog \
	--bannertitle "Support Quick Actions" \
	--message "  " \
	--selecttitle "Device Functions",required \
	--selectvalues "Clear Passcode, Wipe Device, Update Inventory" \
	--bannerimage $bannerimage \
	--titlefont "size=26,shadow=1" \
	--messagefont size=14 \
	--height 400 \
	--width 600 \
	--iconsize 120  \
	--ontop \
	--moveable \
	--position center \
	--quitkey g \
	--button1text "OK" \
	--icon $icon \
	--overlayicon $overlayicon
	--position center)
	
	formatted_answer=$(echo "$answer" | sed 's/:/: /g' | sed 's/"//g')
	function=$(echo "$formatted_answer" | grep "SelectedOption : [^ ]*" | awk '{print $3}')
	echo $function
	
	if [ $function == 'Clear' ] 
	then
		clear_Passcode
		expire_token
	elif [ $function == 'Wipe' ]
	then
		wipe_device
		expire_token
	elif [ $function == 'Update' ]
	then
		update_device_inventory
		expire_token
	else
		echo "Error"
	fi

fi