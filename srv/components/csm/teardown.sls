{% import_yaml 'components/defaults.yaml' as defaults %}
Stage - Reset CSM:
  cmd.run:
    - name: __slot__:salt:setup_conf.conf_cmd('/opt/seagate/eos/csm/conf/setup.yaml', 'csm:reset')

Remove csm package:
  pkg.purged:
    - pkgs:
      - eos-csm_agent
      - eos-csm_web

Delete CSM yum repo:
  pkgrepo.absent:
    - name: {{ defaults.csm.repo.id }}

Delete CSM uploads repo:
  pkgrepo.absent:
    - name: {{ defaults.csm.uploads_repo.id }}

Remove stats collector:
  file.absent:
    - name: /opt/statsd/csm-stats-collector

Remove Symlink:
  file.absent:
    - name: /usr/bin/csm-stats-collector

Remove crontab:
  cron.absent:
    - name: /opt/statsd/csm-stats-collector 10
    - user: root
    - identifier: csm-stats-collector

Delete csm checkpoint flag:
  file.absent:
    - name: /opt/seagate/eos-prvsnr/generated_configs/{{ grains['id'] }}.csm

# TODO TEST
Remove csm user from prvsnrusers group:
  group.present:
    - name: prvsnrusers
    - delusers:
      - csm

Remove csm user from certs group:
  group.present:
    - name: certs
    - delusers:
      - csm
