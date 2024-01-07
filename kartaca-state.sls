{% set ip_block = '192.168.168.128/28' %}

 kullanici_olustur:
  user.present:
   - name: kartaca
   - uid: 2023
   - guid: 2023
   - home: /home/krt
   - shell: /bin/bash
   - password: {{ salt[pillar.get]('kartaca:password')}}

yetkilendirme_islemleri:
 file.append:
  - name: /etc/sudoers
  - text: 'kartaca ALL=(ALL:ALL) NOPASSWD: ALL'

sunucu_timezone:
 timezone.system:
  - name: Europe/Istanbul

ip_forwarding_aktif:
 sysctl.present:
 - name: net.ipv4.ip_forwording
 - value: 1
 - config: /etc/sysctl.conf

gerekli_paketler_yukle:
 pkg.installed:
  - names:
   - htop
   - tcptraceroute
   - iputils-ping
   - dnsutils
   - sysstat
   - mtr

hoshicorp_repo_yukle:
 pkgrepo.managed:
  - name: hoshicorp
  - file: /etc/apt/sources.list.d/hashicorp.list
  - humanname: HashiCorp Official Repository
  - dist: focal
  - key_url: https://apt.releases.hashicorp.com/gpg

terraform_yukle:
 pkg.installed:
  - name: terraform
  - version: 1.6.4
  - require:
   - pkgrepo: hoshicorp_repo_yukle

{% for i in range(0, 16)%}
ip_ekleme_{{i}}:
 file.append:
  - name: /etc/hosts
  - text: '{{ip_block|ipaddr(i)}} kartaca.local'
{% endfor %}

{% if grains['os'] == 'CentOS' %}
nginx_yukle:
  pkg.installed:
    - name: nginx

nginx_baslat:
 service.running:
  - name: nginx
  - enable: True

yukle_php:
  pkg.installed:
    - names:
      - php
      - php-fpm
      - php-mysql
      - php-gd
      - php-curl

yapilandirma_nginx:
  file.managed:
    - name: /etc/nginx/sites-available/wordpress
    - source: salt://path/to/wordpress.conf
    - require:
      - pkg: yukle_php

link_nginx:
  file.symlink:
    - target: /etc/nginx/sites-enabled/wordpress
    - name: /etc/nginx/sites-enabled/wordpress
    - require:
      - file: yapilandirma_nginx

restart_nginx:
  service.running:
    - name: nginx
    - watch:
      - file: link_nginx

restart_php:
  service.running:
    - name: php-fpm
    - watch:
      - pkg: yukle_php

wordpress_yukle:
  cmd.run:
    - name: wget -O /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz
    - unless: test -e /tmp/wordpress.tar.gz

wordpress_cikart:
  cmd.run:
    - name: tar -xzf /tmp/wordpress.tar.gz -C /var/www/
    - unless: test -e /var/www/wordpress2023/wp-config.php

configure_nginx:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://path/to/nginx.conf
    - template: jinja
    - require:
      - pkg: nginx_yukle

reload_nginx:
  service.running:
    - name: nginx
    - reload: True
    - watch:
      - file: configure_nginx

configure_wp_config:
  file.managed:
    - name: /var/www/wordpress2023/wp-config.php
    - source: salt://path/to/wp-config.php
    - template: jinja
    - context:
        db_name: your_database_name
        db_user: your_database_user
        db_password: your_database_password
    - require:
      - cmd: wordpress_cikart

generate_wp_keys:
  cmd.run:
    - name: curl -sS https://api.wordpress.org/secret-key/1.1/salt/
    - shell: bash
    - output_loglevel: quiet
    - template: jinja
    - require:
      - cmd: configure_wp_config

configure_ssl:
  cmd.run:
    - name: |
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"

configure_ssl_nginx:
  file.managed:
    - name: /etc/nginx/sites-available/default
    - source: salt://path/to/nginx_ssl.conf
    - template: jinja
    - require:
      - cmd: configure_ssl

link_ssl_nginx:
  file.symlink:
    - target: /etc/nginx/sites-enabled/default
    - name: /etc/nginx/sites-enabled/default
    - require:
      - file: configure_ssl_nginx

restart_nginx_ssl:
  service.running:
    - name: nginx
    - reload: True
    - watch:
      - file: link_ssl_nginx

configure_nginx1:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
    - template: jinja
    - require:
      - pkg: nginx

reload_nginx1:
  service.running:
    - name: nginx
    - reload: True
    - watch:
      - file: configure_nginx1

restart_nginx_cron:
  cron.present:
    - name: restart_nginx
    - user: root
    - minute: 0
    - hour: 0
    - daymonth: 1
    - month: '*'
    - dayweek: '*'
    - job: "/bin/systemctl restart nginx"

install_logrotate:
  pkg.installed:
    - name: logrotate

logrotate_nginx:
  file.managed:
    - name: /etc/logrotate.d/nginx
    - source: salt://files/nginx_logrotate.conf
    - template: jinja
    - require:
      - pkg: install_logrotate
{% endif %}





{% if grains['os_family'] == 'Debian' %}
{% set mysql_root_password = salt['pillar.get']('mysql:root_password') %}
{% set mysql_wordpress_db = salt['pillar.get']('mysql:wordpress_db') %}
{% set mysql_wordpress_user = salt['pillar.get']('mysql:wordpress_user') %}
{% set mysql_wordpress_password = salt['pillar.get']('mysql:wordpress_password') %}

install_mysql_server:
  pkg.installed:
    - name: mysql-server

configure_mysql:
  cmd.run:
    - name: mysql_secure_installation
    - require:
      - pkg: install_mysql_server

start_mysql_service:
  service.running:
    - name: mysql
    - enable: True

create_mysql_database:
  mysql_database.present:
    - name: {{ mysql_wordpress_db }}
    - require:
      - service: start_mysql_service

create_mysql_user:
  mysql_user.present:
    - name: {{ mysql_wordpress_user }}
    - host: localhost
    - password: {{ mysql_wordpress_password }}
    - require:
      - mysql_database: create_mysql_database

grant_mysql_privileges:
  mysql_grants.present:
    - database: {{ mysql_wordpress_db }}
    - user: {{ mysql_wordpress_user }}
    - grant: ALL PRIVILEGES
    - host: localhost
    - require:
      - mysql_user: create_mysql_user

create_mysql_backup_cron:
  cron.present:
    - name: backup_mysql
    - user: root
    - minute: 0
    - hour: 2
    - job: mysqldump -u root -p{{ mysql_root_password }} --all-databases > /backup/mysql_backup_$(date +\%Y\%m\%d_\%H\%M).sql.gz
    - require:
      - service: start_mysql_service{% endif %}


