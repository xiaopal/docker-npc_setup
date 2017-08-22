FROM alpine:3.6

ARG ALPINE_MIRROR=http://mirrors.aliyun.com/alpine
ARG NPC_DL_MIRROR=http://npc.nos-eastchina1.126.net/dl

RUN echo -e "$ALPINE_MIRROR/v3.6/main\n$ALPINE_MIRROR/v3.6/community" >/etc/apk/repositories \
	&& apk add --no-cache bash curl openssh-client git \
	&& curl "$NPC_DL_MIRROR/dumb-init_1.2.0_amd64.tar.gz" | tar -zx -C /usr/bin \
	&& ansible-galaxy install xiaopal.npc_setup \
	&& ansible-playbook /etc/ansible/roles/xiaopal.npc_setup/tests/noop.yml

ADD scripts /
RUN chmod a+x /*.sh

EXPOSE 9000
CMD ["/run.sh"]

