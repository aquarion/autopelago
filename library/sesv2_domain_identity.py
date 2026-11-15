#!/usr/bin/python
# -*- coding: utf-8 -*-
"""Ansible module to manage an SES v2 domain identity verified via Easy DKIM."""

import time

try:
    from botocore.exceptions import BotoCoreError
    from botocore.exceptions import ClientError
except ImportError:
    pass  # caught by AnsibleAWSModule

from ansible_collections.amazon.aws.plugins.module_utils.botocore import is_boto3_error_code
from ansible_collections.amazon.aws.plugins.module_utils.core import AnsibleAWSModule
from ansible_collections.amazon.aws.plugins.module_utils.retries import AWSRetry

DOCUMENTATION = r"""
---
module: sesv2_domain_identity
short_description: Manage an SES v2 domain identity verified via Easy DKIM
description:
    - Creates or removes an SES domain identity using the SESv2 API.
    - Domain ownership is verified purely via the three Easy DKIM CNAME
      records AWS generates (no separate C(_amazonses) TXT record needed).
    - The C(community.aws.ses_identity) module only wraps the older SES v1
      API, which does not expose DKIM tokens, hence this local module.
options:
    identity:
        description: The domain to verify as an SES identity.
        required: true
        type: str
    state:
        description: Whether the identity should be present or absent.
        default: present
        choices: [present, absent]
        type: str
extends_documentation_fragment:
    - amazon.aws.common.modules
    - amazon.aws.region.modules
    - amazon.aws.boto3
"""

EXAMPLES = r"""
- name: Ensure pdforums.larp.me SES domain identity exists
  sesv2_domain_identity:
    identity: pdforums.larp.me
    state: present
    profile: aqcom
    region: eu-west-1
  register: pdforums_ses_identity
"""

RETURN = r"""
identity:
    description: The domain identity.
    returned: success
    type: str
dkim_tokens:
    description: The three Easy DKIM tokens used to build the CNAME records.
    returned: success
    type: list
    elements: str
dkim_status:
    description: The DKIM verification status of the identity.
    returned: success
    type: str
verified_for_sending_status:
    description: Whether the identity is verified and able to send.
    returned: success
    type: bool
"""


def get_identity(connection, module, identity):
    """Fetch an SES identity, returning None if it doesn't exist."""

    try:
        return connection.get_email_identity(EmailIdentity=identity, aws_retry=True)
    except is_boto3_error_code("NotFoundException"):
        return None
    except (BotoCoreError, ClientError) as e:  # pylint: disable=duplicate-except
        module.fail_json_aws(e, msg=f"Failed to retrieve SES identity {identity}")
        return None


def wait_for_dkim_tokens(connection, module, identity, retries=4, retry_delay=10):
    """Poll for DKIM tokens to appear, tolerating eventual consistency."""

    existing = None
    for _attempt in range(0, retries + 1):
        existing = get_identity(connection, module, identity)
        tokens = (existing or {}).get("DkimAttributes", {}).get("Tokens") or []
        if tokens:
            return existing
        time.sleep(retry_delay)
    return existing


def create_or_update_identity(connection, module):
    """Ensure the domain identity exists and report its DKIM tokens."""

    identity = module.params["identity"]
    existing = get_identity(connection, module, identity)
    changed = False

    if existing is None:
        changed = True
        if not module.check_mode:
            try:
                connection.create_email_identity(EmailIdentity=identity, aws_retry=True)
            except (BotoCoreError, ClientError) as e:
                module.fail_json_aws(e, msg=f"Failed to create SES identity {identity}")
            existing = wait_for_dkim_tokens(connection, module, identity)

    if existing is None:
        # check_mode with no pre-existing identity: nothing to report yet.
        module.exit_json(
            changed=changed,
            identity=identity,
            dkim_tokens=[],
            dkim_status="Pending",
            verified_for_sending_status=False,
        )

    dkim_attributes = existing.get("DkimAttributes", {})
    module.exit_json(
        changed=changed,
        identity=identity,
        dkim_tokens=dkim_attributes.get("Tokens", []),
        dkim_status=dkim_attributes.get("Status"),
        verified_for_sending_status=existing.get("VerifiedForSendingStatus", False),
    )


def destroy_identity(connection, module):
    """Remove the domain identity if it exists."""

    identity = module.params["identity"]
    existing = get_identity(connection, module, identity)
    changed = existing is not None

    if changed and not module.check_mode:
        try:
            connection.delete_email_identity(EmailIdentity=identity, aws_retry=True)
        except (BotoCoreError, ClientError) as e:
            module.fail_json_aws(e, msg=f"Failed to delete SES identity {identity}")

    module.exit_json(changed=changed, identity=identity)


def main():
    """Entry point for the sesv2_domain_identity module."""

    module = AnsibleAWSModule(
        argument_spec={
            "identity": {"required": True, "type": "str"},
            "state": {"default": "present", "choices": ["present", "absent"]},
        },
        supports_check_mode=True,
    )

    connection = module.client("sesv2", retry_decorator=AWSRetry.jittered_backoff())

    if module.params["state"] == "present":
        create_or_update_identity(connection, module)
    else:
        destroy_identity(connection, module)


if __name__ == "__main__":
    main()
