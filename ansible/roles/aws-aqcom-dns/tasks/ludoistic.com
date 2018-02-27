---

#- name: themonthlymoon.com
#  route53_zone: zone=themonthlymoon.com comment="Storytime"

- name: themonthlymoon.com. - A
  route53:
      overwrite: true
      command: "create"
      zone: "themonthlymoon.com"
      record: "themonthlymoon.com."
      type: "A"
      ttl: "300"
      value: '{{ ansible_default_ipv4.address }}'



- name: themonthlymoon.com. - NS
  route53:
      overwrite: true
      command: "create"
      zone: "themonthlymoon.com"
      record: "themonthlymoon.com."
      type: "NS"
      ttl: "172800"
      value: ns-727.awsdns-26.net., ns-1489.awsdns-58.org., ns-1.awsdns-00.com., s-1630.awsdns-11.co.uk.

#- name: themonthlymoon.com. - SOA
#  route53:
#      overwrite: true
#      command: "create"
#      zone: "themonthlymoon.com"
#      record: "themonthlymoon.com."
#      type: "SOA"
#      ttl: "900"
#      value: 'ns-1302.awsdns-34.org. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 86400'



- name: www.themonthlymoon.com. - CNAME
  route53:
      overwrite: true
      command: "create"
      zone: "themonthlymoon.com"
      record: "www.themonthlymoon.com."
      type: "CNAME"
      ttl: "300"
      value: 'themonthlymoon.com'


- name: google._domainkey.themonthlymoon.com. - TXT
  route53:
      overwrite: true
      command: "create"
      zone: "themonthlymoon.com"
      record: "google._domainkey.themonthlymoon.com."
      type: "TXT"
      ttl: "300"
      value: '"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCeXipYp/HVbmCmGSDI5WKA6vB2679OoStEVKXePsMD0WfEOK+BqQv1lHBzjL2AlNvGmMPf2Ccd6cnk0HdsaQqpkbS1TyOWuZx7P191Q1bHhT5mxvZoAdYbv5XN+0j/SWsqhg/2zYmCQhB8ed499sX5esIUWYQK4djh+xV7GaYxCwIDAQAB"'

- name: themonthlymoon.com. - MX
  route53:
      overwrite: true
      command: "create"
      zone: "themonthlymoon.com"
      record: "themonthlymoon.com."
      type: "MX"
      ttl: "300"
      value: '5 ALT1.ASPMX.L.GOOGLE.COM.,5 ALT2.ASPMX.L.GOOGLE.COM.,1 ASPMX.L.GOOGLE.COM.,10 ASPMX2.GOOGLEMAIL.COM.,10 ASPMX3.GOOGLEMAIL.COM.'

