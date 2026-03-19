#!/usr/bin/env bash

######################################################################
# Gabriel (Gabu) Salvador                                            #
# gbsalvador at gmail.com                                            #
#                                                                    #
# André (Magrão) Borali                                              #
# andreborali at gmail.com                                           #
#                                                                    #
# Reviewed by: Google Gemini 3.1 Pro                                 #
#                                                                    #
# Date: 2026-02-21                                                   #
#                                                                    #
# Unofficial script to create a LinuxGSM container                   #
# License: Creative Commons                                          #
######################################################################

######################################################################
#                          GLOBAL VARIABLES                          #
######################################################################

declare -gr VERSION="0.3"
declare -gr oIFS="$IFS"

declare -gi VOLUME

declare -g RED; RED=$(tput setaf 1)
declare -g GREEN; GREEN=$(tput setaf 2)
declare -g BLUE; BLUE=$(tput setaf 4)
declare -g NC; NC=$(tput sgr0)

declare -g GAME
declare -g USERTCP
declare -g USERUDP
declare -g TCPPORTS
declare -g UDPPORTS
declare -g LOCAL_DIR
declare -g VOL_STR

######################################################################
#                             FUNCTIONS                              #
######################################################################

function fn_depcheck() # Check for dependencies
{
	declare DEPCHECK

	for DEPCHECK in "$@"; do
		if ! command -v "${DEPCHECK}" > /dev/null 2>&1; then
			printf "\n%sI need \'%s\' to run this script.%s\n" "${RED}" "${DEPCHECK}" "${NC}"
			exit 1
		fi
	done

	return 0
}

function fn_srvlist() # Process the server list data
{
	declare -a GAMEARRAY
	declare -a GAMEID
	declare -a GAMENAME
	declare -ir NUM=$(wc -l < /tmp/serverlist.csv)
	declare -i X

	while IFS=',' read -ra GAMEARRAY; do
		GAMEID+=("${GAMEARRAY[0]}")
		GAMENAME+=("${GAMEARRAY[2]}")
	done < /tmp/serverlist.csv
	for (( X=0; X < NUM; X++ )); do
		printf '%s¦ %s ¦' "${GAMEID[$X]}" "${GAMENAME[$X]}"
	done

	return 0
}

function fn_menu() # Create the menu
{
	declare GAMESLIST; GAMESLIST=$(fn_srvlist)

	IFS="¦"
	GAME=$(whiptail --menu "Choose a game:" --title "LinuxGSM v${VERSION}" 30 60 22 ${GAMESLIST} 3>&1 1>&2 2>&3)
	declare -i WHIP_STATUS=$?
	IFS="$oIFS"
	if [[ $WHIP_STATUS -ne 0 || -z ${GAME} ]]; then
		printf "\n%sOperation canceled or no game selected. Exiting...%s\n" "${RED}" "${NC}"
		exit 1
	fi

	return 0
}

function fn_varcheck() # Check if variable has a valid string
{
	declare USERPORTS="$1"
	declare -a PORTRANGE
	declare -a PORTLIST
	declare -a RANGETEMP
	declare PORTTEST

	if [[ -n "${USERPORTS}" ]]; then
		if [[ ! ${USERPORTS} =~ ^([0-9]{1,5}\-[0-9]{1,5}|[0-9]{1,5})(\ ([0-9]{1,5}\-[0-9]{1,5}|[0-9]{1,5}))*$ ]]; then
			printf "\n%sSorry, invalid format.\nIt must be like this: 27015 27020-27030 30000%s\n" "${RED}" "${NC}"
			exit 1
		fi
		IFS=' ' read -r -a PORTRANGE <<< "${USERPORTS}"
		USERPORTS=$(echo "${USERPORTS}" | tr "-" " ")
		IFS=' ' read -r -a PORTLIST <<< "${USERPORTS}"
		for PORTTEST in "${PORTLIST[@]}"; do
			if [[ ! ${PORTTEST} =~ [0-9]{4,5} ]]; then
				printf "\n%sPort(s) must be higher than 1024 and lower than 49151.%s\n" "${RED}" "${NC}"
				exit 1
			fi
			if [[ ${PORTTEST} -lt 1025 || ${PORTTEST} -gt 49150 ]]; then
				printf "\n%sPort(s) must be higher than 1024 and lower than 49151.%s\n" "${RED}" "${NC}"
				exit 1
			fi
		done
		for PORTTEST in "${PORTRANGE[@]}"; do
			if [[ ${PORTTEST} =~ \- ]]; then
				PORTTEST=$(echo "${PORTTEST}" | tr "-" " ")
				IFS=' ' read -r -a RANGETEMP <<< "${PORTTEST}"
				if [[ "${RANGETEMP[0]}" -ge "${RANGETEMP[1]}" ]]; then
					printf "\n%sIn a port range, the first value must be lower than the second.%s\n" "${RED}" "${NC}"
					exit 1
				fi
			fi
		done
	fi

	return 0
}

function fn_ports() # Arrange TCP and/or UDP port(s)
{
	declare -a PORTARRAY
	declare -i Y=0
	declare -i Z=0

	if [[ -n "${USERTCP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERTCP}"
		while [ "$Y" -lt "${#PORTARRAY[@]}" ]; do
			TCPPORTS="$TCPPORTS -p ${PORTARRAY[$Y]}:${PORTARRAY[$Y]}/tcp"
			(( Y++ )) || true
		done
	fi
	if [[ -n "${USERUDP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERUDP}"
		while [ "$Z" -lt "${#PORTARRAY[@]}" ]; do
			UDPPORTS="$UDPPORTS -p ${PORTARRAY[$Z]}:${PORTARRAY[$Z]}/udp"
			(( Z++ )) || true
		done
	fi

	return 0
}

######################################################################
#                                MAIN                                #
######################################################################

clear

# Check for dependencies
fn_depcheck "docker" "wget" "whiptail" "wc" "tr"

# Get the latest LinuxGSM server list from GitHub
if ! wget -q -O /tmp/serverlist.csv https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/serverlist.csv > /dev/null 2>&1; then
	printf "\n%sOops! I could not download the servers list.%s\n" "${RED}" "${NC}"
	exit 1
fi

# Remove the header from server list
sed -i '1d' /tmp/serverlist.csv

# Create the menu
fn_menu

# Remove server list temp file
rm /tmp/serverlist.csv

# Check if a container based on this game image already exists
if [[ -n "$(docker ps -a --filter "ancestor=gameservermanagers/gameserver:${GAME}" -q)" ]]; then
	printf "\n%sWARNING!!!%s\n\nA container based on image gameservermanagers/gameserver:%s already exists in Docker.\nPlease, select another game or remove the existing container.\n" "${RED}" "${NC}" "${GAME}"
	exit 1
fi

# Use or create a Docker volume or a local host folder
if docker volume ls | grep -q lgsm-"${GAME}"server; then
	CHOICE=$(whiptail --title "Volume Strategy" --menu "A Docker repository for ${GAME} already exists. How to proceed?" 15 65 2 \
	"1" "Use existing Docker Volume" \
	"2" "Use a LOCAL Host Folder" 3>&1 1>&2 2>&3)
else
	CHOICE=$(whiptail --title "Volume Strategy" --menu "How would you like to store the server files?" 15 65 2 \
	"0" "Create a NEW Docker Volume" \
	"2" "Use a LOCAL Host Folder" 3>&1 1>&2 2>&3)
fi

# Exit if user hits Cancel in the volume menu
if [[ $? -ne 0 ]]; then
	printf "\n%sCanceled by user. Exiting...%s\n" "${RED}" "${NC}"
	exit 1
fi

# Check user's choice and prepare the local folder if needed
case $CHOICE in
	0) VOLUME=0 ;;
	1) VOLUME=1 ;;
	2) VOLUME=2
		LOCAL_DIR=$(whiptail --title "Local Directory" --inputbox "Enter the ABSOLUTE path on your host (e.g., /home/$USER/lgsm-$GAME):" 10 70 3>&1 1>&2 2>&3)
		if [[ $? -ne 0 || -z "$LOCAL_DIR" ]]; then 
			printf "\n%sInvalid path or canceled. Aborting...%s\n" "${RED}" "${NC}"
			exit 1
		fi
		mkdir -p "$LOCAL_DIR" 2>/dev/null
		if [[ $? -ne 0 ]]; then
			printf "\n%sError: Could not create directory %s. Please, check your permissions.%s\n" "${RED}" "${LOCAL_DIR}" "${NC}"
			exit 1
		fi
		;;
	*) printf "\n%sExiting...%s\n" "${RED}" "${NC}"; exit 1 ;;
esac

# Get the TCP port(s) to be exposed
USERTCP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
"Please, enter the TCP Ports to be exposed or leave empty if none.\nSeparate multiple ports with spaces.\nUse a dash for ranges.\n\ne.g.: 27015 27020-27030 30000" 12 70 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
	printf "\n%sCanceled. Exiting...%s\n" "${RED}" "${NC}"
	exit 1
fi

# Check if variable has a valid string
fn_varcheck "${USERTCP}"

# Get the UDP port(s) to be exposed
USERUDP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
"Now, enter the UDP Ports to be exposed or leave empty if none.\nSame as before: Separate multiple ports with spaces\nand a dash for ranges.\n\ne.g.: 27015 27020-27030 30000" 12 70 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
	printf "\n%sCanceled. Exiting...%s\n" "${RED}" "${NC}"
	exit 1
fi

# Check if variable has a valid string
fn_varcheck "${USERUDP}"

# Check if both variables are not empty
if [[ -z ${USERTCP} && -z ${USERUDP} ]]; then
	printf "\n%sYou must type at least one TCP or UDP port.%s\n" "${RED}" "${NC}"
	exit 1
fi

# Arrange TCP and/or UDP port(s)
fn_ports

# Create the container
if (whiptail --title "LinuxGSM v${VERSION}" --yesno "Ready to create a container named ${GAME}.\nProceed?" 10 60); then
	printf "\nI will create the %s%s%s container.\nPlease wait, this may take a while.\n" "${GREEN}" "${GAME}" "${NC}"
	# Prepare the volume string based on strategy
	if [[ "${VOLUME}" == "0" ]]; then
		printf "\nCreating Docker volume lgsm-%sserver to store your game files...\n" "${GAME}"
		docker volume create lgsm-"${GAME}"server > /dev/null 2>&1
		VOL_STR="-v lgsm-${GAME}server:/data"
	elif [[ "${VOLUME}" == "1" ]]; then
		printf "\nUsing Docker volume lgsm-%sserver previously created.\n" "${GAME}"
		VOL_STR="-v lgsm-${GAME}server:/data"
	elif [[ "${VOLUME}" == "2" ]]; then
		printf "\nUsing Local Host Directory: %s\n" "${LOCAL_DIR}"
		VOL_STR="-v \"${LOCAL_DIR}:/data\""
	fi
	printf "\nCreating Docker container %s...\n" "${GAME}"
	# Create a temporary file to capture Docker output/errors
	TMP_DOCKER_OUT=$(mktemp)
	# Run the container and check for success
	if eval docker run -d --init -h "${GAME}" --name lgsm-"${GAME}"server --restart unless-stopped ${VOL_STR} "${TCPPORTS}" "${UDPPORTS}" gameservermanagers/gameserver:"${GAME}" > "${TMP_DOCKER_OUT}" 2>&1; then
		printf "%sDone.%s\n" "${GREEN}" "${NC}"
	else
		printf "\n%sERROR: Container creation failed!%s\n" "${RED}" "${NC}"
		# Show the exact Docker error to the user via whiptail
		whiptail --title "Docker Error" --msgbox "Failed to create or start the container.\nThis usually happens if a port is already in use.\n\nDocker output:\n$(cat ${TMP_DOCKER_OUT})" 15 75
		# Cleanup: Remove the dead container if it was partially created
		docker rm -f lgsm-"${GAME}"server > /dev/null 2>&1
		rm -f "${TMP_DOCKER_OUT}"
		exit 1
	fi
	rm -f "${TMP_DOCKER_OUT}"
else
	printf "\nAborting...\n"
	exit 1
fi

exit 0
