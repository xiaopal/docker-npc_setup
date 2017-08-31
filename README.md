蜂巢云主机编排代理
===

开始使用
---
```
# 在本地运行容器（Ctrl+C 结束）
$ docker run -it --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    -e GIT_URL=https://github.com/xiaopal/npc-launch-repo.git \
    xiaopal/npc_setup

# 在本地运行容器（运行一次后退出）
$ docker run -it --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    -e GIT_URL=https://github.com/xiaopal/npc-launch-repo.git \
    -e NPC_SETUP_ONCE=Y \
    xiaopal/npc_setup

# 创建为蜂巢容器服务
$ docker run -i --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    -e SERVICE_NS=fnd \
    -e SERVICE_NAME=npc-setup \
    xiaopal/npc_setup bash <<\EOF
        NS_ID="$(npc api 'json.namespaces[]|select(.display_name==env.SERVICE_NS)|.id//empty' GET /api/v1/namespaces)"
        [ -z "$NS_ID" ] && NS_ID="$(npc api '.namespace_id//.namespace_Id//empty' POST /api/v1/namespaces "$(jq -nc '{name: env.SERVICE_NS}')")"
        [ ! -z "$NS_ID" ] && npc api POST /api/v1/microservices "$(jq -nc \
            --arg ns "$NS_ID" \
            '{
                bill_info:"default",
                service_info: {
                    service_name: env.SERVICE_NAME, namespace_id: $ns, 
                    port_maps: [{"target_port": "80","port": "80","protocol": "TCP"}],
                    stateful: 1, replicas: 1, spec_alias: "C1M1S20", disk_type: 2, 
                    state_public_net:{used: false, type: "flow", bandwidth: 1}
                },
                service_container_infos: [{
                    image_path: "hub.c.163.com/xiaopal/npc_setup:latest",
                    container_name: env.SERVICE_NAME,
                    envs: ({
                        NPC_API_KEY: env.NPC_API_KEY,
                        NPC_API_SECRET: env.NPC_API_SECRET,
                        GIT_URL: "https://github.com/xiaopal/npc-launch-repo.git",
                        NPC_WEBHOOK: "/webhook/npc-setup",
                        ANSIBLE_SSH_CONTROL_PATH: "/dev/shm/npc-cp-%%h-%%p-%%r"
                    }|to_entries), 
                    log_dirs: [], cpu_weight: 100, memory_weight: 100, local_disk_info: [], volume_info:{}
                }]
            }')"
EOF
$ docker run -i --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    -e SERVICE_NS=fnd \
    -e SERVICE_NAME=npc-setup-secure \
    xiaopal/npc_setup bash <<\EOF
        NS_ID="$(npc api 'json.namespaces[]|select(.display_name==env.SERVICE_NS)|.id//empty' GET /api/v1/namespaces)"
        [ -z "$NS_ID" ] && NS_ID="$(npc api '.namespace_id//.namespace_Id//empty' POST /api/v1/namespaces "$(jq -nc '{name: env.SERVICE_NS}')")"
        [ ! -z "$NS_ID" ] && npc api POST /api/v1/microservices "$(jq -nc \
            --arg ns "$NS_ID" \
            --arg sec "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)" \
            '{
                bill_info:"default",
                service_info: {
                    service_name: env.SERVICE_NAME, namespace_id: $ns, 
                    port_maps: [{"target_port": "80","port": "80","protocol": "TCP"}],
                    stateful: 1, replicas: 1, spec_alias: "C1M1S20", disk_type: 2, 
                    state_public_net:{used: false, type: "flow", bandwidth: 1}
                },
                service_container_infos: [{
                    image_path: "hub.c.163.com/xiaopal/npc_setup:latest",
                    container_name: env.SERVICE_NAME,
                    envs: ({
                        NPC_API_KEY: env.NPC_API_KEY,
                        NPC_API_SECRET: env.NPC_API_SECRET,
                        GIT_URL: "https://github.com/xiaopal/npc-launch-repo.git",
                        NPC_WEBHOOK: "/webhook/npc-setup",
                        NPC_WEBHOOK_METHOD: "POST",
                        NPC_WEBHOOK_SECRET: $sec,
                        NPC_WEBHOOK_OPTIONS: "set_real_ip_from 10.0.0.0/8; allow 192.30.252.0/22; allow 185.199.108.0/22; deny all;",
                        ANSIBLE_SSH_CONTROL_PATH: "/dev/shm/npc-cp-%%h-%%p-%%r"
                    }|to_entries), 
                    log_dirs: [], cpu_weight: 100, memory_weight: 100, local_disk_info: [], volume_info:{}
                }]
            }')"
EOF

$ docker run -it --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    -e NPC_SETUP_ONCE=Y \
    -v $PWD/playbook.yml:/playbooks/playbook.yml \
    xiaopal/npc_setup
```
