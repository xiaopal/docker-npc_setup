#!/usr/bin/dumb-init /bin/bash

NPC_SETUP_DIR=${NPC_SETUP_DIR:-/playbooks}
NPC_SETUP_LOCK="${NPC_SETUP_DIR}.lock"
NPC_SETUP_INTERVAL=${NPC_SETUP_INTERVAL:-1m}
NPC_SETUP_RETRY_INTERVAL=${NPC_SETUP_RETRY_INTERVAL:-5s}

prepare(){
	return 0
}

summary(){
	( cd $NPC_SETUP_DIR && find . -type f -printf '%T@%p\n' )
}

do_apply(){
	echo "[ $(date -R) ] INFO - Applying playbooks..."
	cd $NPC_SETUP_DIR || return 1
	[ -f requirements.yml ] && {
		ansible-galaxy install -r requirements.yml || return 1
	}
	PLAYBOOK_ARGS=('-T' '60')
	[ -e 'inventory' ] && PLAYBOOK_ARGS=("${PLAYBOOK_ARGS[@]}" '-i' 'inventory')
	
	for PLAYBOOK in *.yml; do
		[ -f "$PLAYBOOK" ] && [ "$PLAYBOOK" != "requirements.yml" ] && {
			echo "[ $(date -R) ] INFO - Applying $PLAYBOOK..."
			npc playbook "${PLAYBOOK_ARGS[@]}" "$PLAYBOOK" || return 1
		}
	done
	echo "[ $(date -R) ] INFO - Playbooks applied"
	return 0
}

apply_playbooks(){
	local QUEUE=${NPC_SETUP_LOCK}~q
	while true; do
		touch $QUEUE && (flock -n 100) 100>>$NPC_SETUP_LOCK || return 0
		( exec 100>>$NPC_SETUP_LOCK && flock 100 || exit 1
			rm -f $QUEUE
			prepare && [ -d $NPC_SETUP_DIR ] && cd $NPC_SETUP_DIR || {
				echo "[ $(date -R) ] ERROR - Failed to prepare '$NPC_SETUP_DIR'."
				exit 1
			}
			summary | md5sum -c $NPC_SETUP_LOCK &>/dev/null || {
				do_apply && summary | md5sum > $NPC_SETUP_LOCK || exit 1
			}
			exit 0
		) && { [ -f $QUEUE ] && continue || return 0; }
		[ -f $QUEUE ] && continue 
		[ ! -z "$NPC_SETUP_RETRY_INTERVAL" ] || {
			echo "[ $(date -R) ] ERROR - Playbooks failed"
			return 1
		}
		echo "[ $(date -R) ] WARN - Playbooks failed, Retring..."
		sleep $NPC_SETUP_RETRY_INTERVAL
	done
}

[ ! -z "$GIT_URL" ] && { 
	GIT_REPO_DIR="${GIT_REPO_DIR:-/repository}"
	GIT_BRANCH="${GIT_BRANCH:-master}"
	GIT_PATH="${GIT_PATH:-/}"
	NPC_SETUP_DIR="${GIT_REPO_DIR%/}/${GIT_PATH#/}"
	NPC_SETUP_LOCK="${GIT_REPO_DIR%/}.lock"

	[ ! -f ~/.ssh/id_rsa ] && {
		echo "[ $(date -R) ] INFO - Generate ssh-key..."
		cat /dev/zero | ssh-keygen -q -N "" && echo ' '
	}

	( 
		echo 'StrictHostKeyChecking no' 
		echo 'UserKnownHostsFile /dev/null'
	) > ~/.ssh/config 

	[ -d /.ssh ] && [ -f /.ssh/id_rsa ] && {
		echo "[ $(date -R) ] INFO - Override ssh-key..."
		cat /.ssh/id_rsa > ~/.ssh/id_rsa
		[ -f /.ssh/id_rsa.pub ] && cat /.ssh/id_rsa.pub > ~/.ssh/id_rsa.pub
	}

	[ -f ~/.ssh/id_rsa.pub ] && {
		echo "[ $(date -R) ] INFO - SSH PUBLIC KEY: $(cat ~/.ssh/id_rsa.pub)"
	}

	summary(){
		( cd $GIT_REPO_DIR && git rev-parse HEAD )
	}

	prepare(){
		clone_repo
		( cd $GIT_REPO_DIR && git reset --hard -q HEAD && git pull | sed 1d && exit ${PIPESTATUS[0]} )
	}

	clone_repo(){
		[ ! -d $GIT_REPO_DIR ] && {
			echo "[ $(date -R) ] INFO - Clone '$GIT_URL'(branch=${GIT_BRANCH})..."
			git clone "$GIT_URL" --branch "${GIT_BRANCH}" --single-branch $GIT_REPO_DIR
		}
	}

	clone_repo
}

cleanup() {
	[ ! -z "$1" ] \
		&& echo "[ $(date -R) ] WARN - Caught $1 signal! Shutting down..." \
		|| echo "[ $(date -R) ] INFO - Finishing..."
	trap - EXIT INT TERM
	exit 0
}
trap 'cleanup INT'  INT
trap 'cleanup TERM' TERM
trap 'cleanup' EXIT

[ ! -z "$NPC_WEBHOOK" ] && {
	WEBHOOK="Webhook 'http://localhost${NPC_WEBHOOK_PORT:+:${NPC_WEBHOOK_PORT:-80}}$NPC_WEBHOOK'"
	while true; do 
		WEBHOOK_PATH="/${NPC_WEBHOOK#/}" \
		WEBHOOK_TOKEN="$NPC_WEBHOOK_TOKEN" \
			nc -l -p ${NPC_WEBHOOK_PORT:-80} -e /webhook.sh && { 
				echo "[ $(date -R) ] INFO - $WEBHOOK triggered"
				apply_playbooks &
			}
	done &
	echo "[ $(date -R) ] INFO - $WEBHOOK started"
}

[[ "$NPC_SETUP_INTERVAL" =~ ^(false|no|none|never|0|-1)$ ]] && NPC_SETUP_INTERVAL=
[[ "$NPC_SETUP_RETRY_INTERVAL" =~ ^(false|no|none|never|0|-1)$ ]] && NPC_SETUP_RETRY_INTERVAL=
[ ! -z "$NPC_SETUP_INTERVAL" ] && while true; do
	[[ "$NPC_SETUP_INTERVAL" = "once" ]] && {
		NPC_SETUP_INTERVAL=
		NPC_SETUP_RETRY_INTERVAL=
	}  
	apply_playbooks
	[ ! -z "$NPC_SETUP_INTERVAL" ] || break
	sleep $NPC_SETUP_INTERVAL
done
wait