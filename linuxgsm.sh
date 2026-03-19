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

declare -gr VERSION="0.4"
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
	declare -a TOKENS
	declare -a RANGE_PARTS
	declare -a PORTLIST
	declare -a RANGETEMP
	declare PORTTEST
	declare HOSTPART
	declare CONTPART

	if [[ -n "${USERPORTS}" ]]; then
		# Accept formats like: 27015 | 7777:27015 | 0.0.0.0:7777:27015
		# Also allow ranges: 27015-27030 or 7777-7780:27015-27018
		# Support Docker-style "->" and optional /tcp or /udp suffixes.
		USERPORTS=$(echo "${USERPORTS}" | sed -E 's/->/:/g' | sed -E 's/\/(tcp|udp)//g')

		IFS=' ' read -r -a TOKENS <<< "${USERPORTS}"
		for PORTTEST in "${TOKENS[@]}"; do
			# Split host/container parts if provided
			IFS=':' read -r -a RANGE_PARTS <<< "${PORTTEST}"
			if [[ ${#RANGE_PARTS[@]} -eq 1 ]]; then
				HOSTPART="${RANGE_PARTS[0]}"
				CONTPART="${RANGE_PARTS[0]}"
			elif [[ ${#RANGE_PARTS[@]} -eq 2 ]]; then
				HOSTPART="${RANGE_PARTS[0]}"
				CONTPART="${RANGE_PARTS[1]}"
			elif [[ ${#RANGE_PARTS[@]} -eq 3 ]]; then
				# IP:host:container notation
				HOSTPART="${RANGE_PARTS[1]}"
				CONTPART="${RANGE_PARTS[2]}"
			else
				printf "\n%sSorry, invalid format.\nUse host:container or just the port number.%s\n" "${RED}" "${NC}"
				exit 1
			fi

			# Validate the host and container port ranges individually
			for PORTTEST in "${HOSTPART}" "${CONTPART}"; do
				if [[ ! ${PORTTEST} =~ ^[0-9]{1,5}(-[0-9]{1,5})?$ ]]; then
					printf "\n%sSorry, invalid port format.\nIt must be like: 27015 or 7777:27015 or 27020-27030%s\n" "${RED}" "${NC}"
					exit 1
				fi

				PORTLIST=()
				if [[ ${PORTTEST} =~ - ]]; then
					PORTLIST=(${PORTTEST//-/ })
				else
					PORTLIST=("${PORTTEST}")
				fi

				for PORTTEST in "${PORTLIST[@]}"; do
					if [[ ${PORTTEST} -lt 1025 || ${PORTTEST} -gt 49150 ]]; then
						printf "\n%sPort(s) must be higher than 1024 and lower than 49151.%s\n" "${RED}" "${NC}"
						exit 1
					fi
				done

				if [[ ${#PORTLIST[@]} -eq 2 && ${PORTLIST[0]} -ge ${PORTLIST[1]} ]]; then
					printf "\n%sIn a port range, the first value must be lower than the second.%s\n" "${RED}" "${NC}"
					exit 1
				fi
			done

			# If both sides are ranges, ensure they have the same size.
			if [[ "${HOSTPART}" =~ - && "${CONTPART}" =~ - ]]; then
				IFS='-' read -r -a RANGETEMP <<< "${HOSTPART}"
				declare -i HOST_LEN=$((RANGETEMP[1] - RANGETEMP[0]))
				IFS='-' read -r -a RANGETEMP <<< "${CONTPART}"
				declare -i CONT_LEN=$((RANGETEMP[1] - RANGETEMP[0]))
				if [[ ${HOST_LEN} -ne ${CONT_LEN} ]]; then
					printf "\n%sWhen mapping port ranges, both sides must have the same size.%s\n" "${RED}" "${NC}"
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
	declare TOKEN

	if [[ -n "${USERTCP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERTCP}"
		while [ "$Y" -lt "${#PORTARRAY[@]}" ]; do
			TOKEN="${PORTARRAY[$Y]}"
			TOKEN="${TOKEN%/tcp}"
			TOKEN="${TOKEN%/udp}"
			TOKEN="${TOKEN//->/:}"
			if [[ "${TOKEN}" =~ : ]]; then
				TCPPORTS="$TCPPORTS -p ${TOKEN}/tcp"
			else
				TCPPORTS="$TCPPORTS -p ${TOKEN}:${TOKEN}/tcp"
			fi
			(( Y++ )) || true
		done
	fi
	if [[ -n "${USERUDP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERUDP}"
		while [ "$Z" -lt "${#PORTARRAY[@]}" ]; do
			TOKEN="${PORTARRAY[$Z]}"
			TOKEN="${TOKEN%/tcp}"
			TOKEN="${TOKEN%/udp}"
			TOKEN="${TOKEN//->/:}"
			if [[ "${TOKEN}" =~ : ]]; then
				UDPPORTS="$UDPPORTS -p ${TOKEN}/udp"
			else
				UDPPORTS="$UDPPORTS -p ${TOKEN}:${TOKEN}/udp"
			fi
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
"Enter TCP port mappings to expose (host:container). Leave empty if none.\nSeparate multiple entries with spaces.\nUse a dash for ranges (same length on both sides).\n\ne.g.: 27015 7777:27015 0.0.0.0:7777:27015 27020-27030" 12 70 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
	printf "\n%sCanceled. Exiting...%s\n" "${RED}" "${NC}"
	exit 1
fi

# Check if variable has a valid string
fn_varcheck "${USERTCP}"

# Get the UDP port(s) to be exposed
USERUDP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
"Now, enter UDP port mappings to expose (host:container). Leave empty if none.\nSeparate multiple entries with spaces.\nUse a dash for ranges (same length on both sides).\n\ne.g.: 27015 7777:27015 27020-27030" 12 70 3>&1 1>&2 2>&3)
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
	DOCKER_CMD="docker run -d --init -h \"${GAME}\" --name lgsm-${GAME}server --restart unless-stopped ${VOL_STR} ${TCPPORTS} ${UDPPORTS} gameservermanagers/gameserver:\"${GAME}\""
	printf "\n%s\n" "Command: ${DOCKER_CMD}"
	if eval "${DOCKER_CMD}" > "${TMP_DOCKER_OUT}" 2>&1; then
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
