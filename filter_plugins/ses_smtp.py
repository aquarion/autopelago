"""Ansible filter plugin to derive an SES SMTP password from an IAM secret key.

Implements AWS's documented SigV4-derived conversion:
https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html
"""

import base64
import hmac
import hashlib

from ansible.plugins.filter.core import FilterModule as FilterModuleBase

_DATE = "11111111"
_SERVICE = "ses"
_TERMINAL = "aws4_request"
_MESSAGE = "SendRawEmail"
_VERSION = 0x04


def _sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


class FilterModule(FilterModuleBase):
    """Ansible filter plugin to derive SES SMTP passwords."""

    def filters(self):
        """Return the filter functions provided by this plugin."""
        return {"ses_smtp_password": self.ses_smtp_password}

    def ses_smtp_password(self, secret_access_key: str, region: str) -> str:
        """Derive the SES SMTP password for an IAM secret access key."""

        signature = _sign(("AWS4" + secret_access_key).encode("utf-8"), _DATE)
        signature = _sign(signature, region)
        signature = _sign(signature, _SERVICE)
        signature = _sign(signature, _TERMINAL)
        signature = _sign(signature, _MESSAGE)
        signature_and_version = bytes([_VERSION]) + signature
        return base64.b64encode(signature_and_version).decode("utf-8")
