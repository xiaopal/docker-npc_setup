#!/usr/bin/dumb-init /bin/bash

NPC_SETUP_DIR=${NPC_SETUP_DIR:-/playbooks}
NPC_SETUP_LOCK="${NPC_SETUP_DIR}.lock"
NPC_SETUP_INTERVAL=${NPC_SETUP_INTERVAL:-1m}
NPC_SETUP_RETRY_INTERVAL=${NPC_SETUP_RETRY_INTERVAL:-5s}
[[ "$NPC_SETUP_INTERVAL" = "once" ]] && {
	NPC_SETUP_INTERVAL=
	NPC_SETUP_RETRY_INTERVAL=
}
[[ "$NPC_SETUP_INTERVAL" =~ ^(none|never|0|-1)$ ]] && NPC_SETUP_INTERVAL=
[[ "$NPC_SETUP_RETRY_INTERVAL" =~ ^(none|never|0|-1)$ ]] && NPC_SETUP_RETRY_INTERVAL=

prepare(){
	return 0
}

summary(){
	( cd $NPC_SETUP_DIR && find . -type f -printf '%T@%p\n' )
}

[ ! -z "$GIT_URL" ] && { 
	GIT_REPO_DIR=${GIT_REPO_DIR:-/playbooks.repo}
	NPC_SETUP_DIR="${GIT_REPO_DIR}/${GIT_PATH#/}"
	NPC_SETUP_LOCK="${GIT_REPO_DIR}.lock"

	[ ! -f ~/.ssh/id_rsa ] && {
		cat /dev/zero | ssh-keygen -q -N ""
	}

	( 
		echo 'StrictHostKeyChecking no' 
		echo 'UserKnownHostsFile /dev/null'
	) > ~/.ssh/config 

	[ -d /.ssh ] && [ -f /.ssh/id_rsa ] && {
		echo "[ $(date -R) ] INFO - Override ssh keys..."
		cat /.ssh/id_rsa > ~/.ssh/id_rsa
		[ -f /.ssh/id_rsa.pub ] && cat /.ssh/id_rsa.pub > ~/.ssh/id_rsa.pub
	}

	[ -f ~/.ssh/id_rsa.pub ] && {
		echo "[ $(date -R) ] INFO - SSH PUBLIC KEY: $(cat ~/.ssh/id_rsa.pub)"
	}

	prepare(){
		[ ! -d $GIT_REPO_DIR ] && git clone $GIT_URL --branch ${GIT_BRANCH:-master} --single-branch $GIT_REPO_DIR
		( cd $GIT_REPO_DIR && git reset --hard -q HEAD && git pull -q )
	}

	summary(){
		( cd $GIT_REPO_DIR && git rev-parse HEAD )
	}

	[ "$GIT_WEBHOOK" != "false" ] && {
		WEBHOOK="Webhook 'http://$(hostname):9999${GIT_WEBHOOK:-/webhook}'"
		while true; do 
			nc -l -p ${GIT_WEBHOOK_PORT:-9000} -e /webhook.sh && { 
				echo "[ $(date -R) ] INFO - $WEBHOOK triggered"
				apply_playbooks &
			}
		done &
		echo "[ $(date -R) ] INFO - $WEBHOOK started"
	}
}


apply_playbooks(){
	while true; do
		( exec 100>>$NPC_SETUP_LOCK && flock 100 || exit 1
			prepare && [ -d $NPC_SETUP_DIR ] && cd $NPC_SETUP_DIR || {
				echo "[ $(date -R) ] ERROR - Failed to prepare '$NPC_SETUP_DIR'." >&2
				exit 1
			}
			summary | md5sum -c $NPC_SETUP_LOCK &>/dev/null || {
				echo '[ $(date -R) ] INFO - Applying playbooks...'
				cd $NPC_SETUP_DIR || exit 1
				[ -f requirements.yml ] && {
					ansible-galaxy install -r requirements.yml || exit 1
				}
				for PLAYBOOK in *.yml; do
					[ -f "$PLAYBOOK" ] && [ "$PLAYBOOK" != "requirements.yml" ] && {
						echo "[ $(date -R) ] INFO - Applying $PLAYBOOK..."
						npc playbook -T 60 "$PLAYBOOK" || exit 1
					}
				done
				echo '[ $(date -R) ] INFO - Playbooks applied'
				summary | md5sum > $NPC_SETUP_LOCK && exit 0
			}
		) && return 0
		[ ! -z "$NPC_SETUP_RETRY_INTERVAL" ] || {
			echo '[ $(date -R) ] ERROR - Playbooks failed'
			return 1
		}
		echo '[ $(date -R) ] WARN - Playbooks failed, Retring...'
		sleep $NPC_SETUP_RETRY_INTERVAL
	done
}

cleanup() {
	[ ! -z "$1" ] \
		&& echo "[ $(date -R) ] INFO - Caught $1 signal! Shutting down..." \
		|| echo "[ $(date -R) ] INFO - Shutting down..."
	trap - EXIT INT TERM
	exit 0
}
trap 'cleanup INT'  INT
trap 'cleanup TERM' TERM
trap 'cleanup' EXIT

while true; do
	apply_playbooks
	[ ! -z "$NPC_SETUP_INTERVAL" ] || break
	sleep $NPC_SETUP_INTERVAL
done
wait