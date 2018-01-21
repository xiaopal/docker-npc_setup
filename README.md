蜂巢云主机编排代理
===

updated 2018-01-21 

新版VPC支持 (NEW)
---
```
$ docker run -i --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    xiaopal/npc_setup npc playbook --setup <<\EOF
---
npc_ssh_key: { name: test-ssh-key }

npc_instances:
  - name: vpc-instance-01
    zone: cn-east-1b
    instance_type: {series: 2, type: 2, cpu: 4, memory: 8G}
    instance_image: Debian 8.6
    vpc: test-vpc
    vpc_subnet: default
    vpc_security_group: test_group
    vpc_inet: yes
    vpc_inet_capacity: 10m
    present: yes

npc_vpc_networks:
  - name: test-vpc
    present: yes
    cidr: 10.177.0.0/16
    subnets:
      - subnet: default/10.177.231.0/24
        zone: cn-east-1b
      - subnet: 10.177.232.0/24
        zone: cn-east-1b
    security_groups:
      - security_group: test_group
        rules:
          - rule: ingress, 0.0.0.0/0, icmp
          - rule: ingress, default, all
          - rule: ingress, 10.0.0.0/8, {icmp,tcp/22,tcp/80,tcp/443,tcp/8000-9000}
          - rule: egress, 10.0.0.1, tcp/80-90
            present: no
      - security_group: unuse_group
        present: no
    route_tables:
      - route_table: '{main_route_table,test_table}'
        routes:
          - route: 192.168.99.0/24
            via_instance: vpc-instance-01
EOF

```

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

$ docker run -i --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    xiaopal/npc_setup npc playbook - <<\EOF
---
- hosts: localhost
  connection: local
  gather_facts: 'no'
  roles: 
    - role: xiaopal.npc_setup
      npc_config:
        ssh_key: 
          name: ansible
      npc_instances: 
        - name: 'ha-nginx-{a,b}'
          instance_image: Debian 8.6
          instance_type:
            cpu: 1
            memory: 2G 
          groups:
            - nginx
          wan_ip: any
          ssh_host_by: wan_ip
          vars:
            vrrp_priority: '*:{150,100}'
            vrrp_state: '*:{BACKUP,BACKUP}'
            vrrp_vip: '10.173.39.250'
  tasks:
    - wait_for: port=22 host="{{npc.instances[item].wan_ip}}" search_regex=OpenSSH delay=5
      with_inventory_hostnames:
        - nginx
- hosts: nginx
  tasks:
    - apt: name=nginx state=present update_cache=true
    - apt: name=keepalived state=present
    - copy:
        dest: /etc/keepalived/keepalived.conf
        content: |
          vrrp_script check_nginx {
              script "/bin/bash -c 'kill -0 $(</var/run/nginx.pid)'"
              weight -60
              interval 1
              fall 1
              rise 1
          }
          vrrp_instance VI_1 {
              state {{vrrp_state}}
              interface eth0
              virtual_router_id 21
              priority {{vrrp_priority}}
              nopreempt
              advert_int 1
              authentication {
                  auth_type PASS
                  auth_pass Password
              }
              virtual_ipaddress {
                  {{vrrp_vip}}
              }
              track_script {
                check_nginx
              }
          }
    - copy:
        dest: /var/www/html/index.html
        content: |
          <!DOCTYPE html>
          <html>
          <head>
          <title>{{npc_instance.name}}</title>
          </head>
          <body>
          <h1>{{npc_instance.name}} - {{npc_instance.lan_ip}}</h1>
          <pre>{{npc_instance|to_json}}</pre>
          </body>
          </html>
    - service: name=nginx state=restarted
    - service: name=keepalived state=restarted
EOF


$ docker run -i --rm \
    -e NPC_API_KEY=<API_KEY> \
    -e NPC_API_SECRET=<API_SECRET> \
    xiaopal/npc_setup npc playbook --setup <<\EOF
---
npc_instances: 
  - name: 'ha-nginx-{a,b}'
    present: false
EOF




```
