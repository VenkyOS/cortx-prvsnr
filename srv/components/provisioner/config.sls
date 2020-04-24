# TODO IMPROVE salt configs might go here as well
include:
  - components.misc_pkgs.rsyslog

provisioner_rsyslog_conf_updated:
  file.managed:
    - name: /etc/rsyslog.d/2-prvsnrfwd.conf
    - source: salt://components/provisioner/files/prvsnrfwd.conf
    - makedirs: True
    - watch_in:
      - service: rsyslog_running