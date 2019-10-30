Start HAProxy:
  service.running:
    - name: haproxy

Start slapd:
  service.running:
    - name: slapd

Start s3authserver:
  service.running:
    - name: s3authserver
    - enable: True
    - require:
      - Start slapd