#!/usr/bin/dumb-init /bin/bash

NPC_SETUP_DIR=${NPC_SETUP_DIR:-/playbooks}
NPC_SETUP_LOCK="${NPC_SETUP_DIR}.lock"
NPC_SETUP_INTERVAL=${NPC_SETUP_INTERVAL:-60}
NPC_SETUP_RETRY_INTERVAL=${NPC_SETUP_RETRY_INTERVAL:-5}

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
	( exec 100>>$NPC_SETUP_LOCK && flock 100 || exit 1
		prepare && cd $NPC_SETUP_DIR || {
			echo "[ $(date -R) ] ERROR - Failed to prepare '$NPC_SETUP_DIR'."
			exit 1
		}
		summary | md5sum -c $NPC_SETUP_LOCK &>/dev/null || {
			do_apply && summary | md5sum > $NPC_SETUP_LOCK || {
				echo "[ $(date -R) ] ERROR - Playbooks failed"
				exit 1
			}
		}
		exit 0
	)
}


run_server(){
	[ ! -z "$NPC_SETUP_ONCE" ] && {
		apply_playbooks
		return
	}

	[[ "$NPC_SETUP_INTERVAL" =~ ^(false|no|none|never|0|-1)$ ]] && NPC_SETUP_INTERVAL=
	[[ "$NPC_SETUP_RETRY_INTERVAL" =~ ^(false|no|none|never|0|-1)$ ]] && NPC_SETUP_RETRY_INTERVAL=

	local OPTIONS=( -t 0.1 ) REQUEST RECENT_REQUEST
	echo "[ $(date -R) ] INFO - Starting Webhook '${NPC_WEBHOOK:-/webhook}' over port ${NPC_WEBHOOK_PORT:-80}"
	while true; do
		if read -r "${OPTIONS[@]}" REQUEST; then
			[ -z "$RECENT_REQUEST" ] && {
				webhook_check_request "$REQUEST" || {
					echo "[ $(date -R) ] WARN - Illegal webhook request: $REQUEST"
					continue
				} 
				RECENT_REQUEST="$REQUEST"
				echo "[ $(date -R) ] INFO - Webhoook triggered by $(jq -r '.remote_addr'<<<"$REQUEST")"
			}
			OPTIONS=( -t 0.1 )
		elif (($? > 128)); then
			[ ! -z "$NPC_SETUP_INTERVAL" ] && OPTIONS=( -t $NPC_SETUP_INTERVAL ) || {
				OPTIONS=()
				[ ! -z "$RECENT_REQUEST" ] || continue
			}
			apply_playbooks || {
				[ ! -z "$NPC_SETUP_RETRY_INTERVAL" ] && OPTIONS=( -t $NPC_SETUP_RETRY_INTERVAL ) && continue
			}
			[ ! -z "$RECENT_REQUEST" ] && RECENT_REQUEST=
		else
			return
		fi
	done < <(nginx -qc /webhook.conf)
}

webhook_check_request(){
	local REQUEST="$1"
	[ ! -z "$NPC_WEBHOOK_METHOD" ] && {
		jq -ce 'select(.method == env.NPC_WEBHOOK_METHOD)'<<<"$REQUEST" > /dev/null || return 1
	}
	[ ! -z "$NPC_WEBHOOK_SECRET" ] && {
		jq -ce 'select(.gitlab_secret == env.NPC_WEBHOOK_SECRET)'<<<"$REQUEST" > /dev/null && return 0
		local GITHUB_SIGNATURE="$(jq -r '.github_signature//empty'<<<"$REQUEST")" \
			&& [ ! -z "$GITHUB_SIGNATURE" ] \
			&& [ "${GITHUB_SIGNATURE}" = "$(webhook_github_signature<<<"$REQUEST")" ] \
			&& return 0
		return 1
	}
	return 0
}

webhook_github_signature(){
	echo -n "$(jq -r '.body//empty')" \
		| openssl sha1 -hmac "$NPC_WEBHOOK_SECRET" \
		| cut -d ' ' -f 2 \
		| xargs printf 'sha1=%s'
}

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

[ ! -z "$GIT_URL" ] && { 
	GIT_REPO_DIR="${GIT_REPO_DIR:-/repository}"
	GIT_BRANCH="${GIT_BRANCH:-master}"
	GIT_PATH="${GIT_PATH:-/}"
	NPC_SETUP_DIR="${GIT_REPO_DIR%/}/${GIT_PATH#/}"
	NPC_SETUP_LOCK="${GIT_REPO_DIR%/}.lock"

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

cat<<EOF >/webhook.conf && run_server 
daemon off;
worker_processes 1;
pid /nginx.pid;
error_log /dev/stderr warn;
events {}
http {
    types {}
    default_type application/json;
    log_format req escape=json '{'
        '"method":"\$request_method",'
        '"uri":"\$request_uri",'
        '"remote_addr":"\$remote_addr",'
        '"gitlab_token":"\$http_x_gitlab_token",'
        '"github_signature":"\$http_x_hub_signature",'
        '"body":"\$request_body"'
        '}';
    access_log off;
    server_tokens off;
    server {
        listen ${NPC_WEBHOOK_PORT:-80} default_server;
        root /dev/null;
        error_page 400 = @reject;
        error_page 403 = @forbidden;

        location / {
            return 400;
        }

        location ${NPC_WEBHOOK:-/webhook} {
            $NPC_WEBHOOK_OPTIONS
            proxy_pass http://127.0.0.1${NPC_WEBHOOK_PORT:+:$NPC_WEBHOOK_PORT}/ok;
            access_log /dev/stdout req;
        }

        location /ok {
            return 200 '{"message":"ok"}';
        }
        location @reject {
            return 400 '{"message":"bad request"}';
        }
        location @forbidden {
            return 403 '{"message":"forbidden"}';
        }
    }
}
EOF