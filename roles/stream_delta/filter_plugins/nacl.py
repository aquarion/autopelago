"""Ansible filter plugin to encrypt secrets for GitHub using PyNaCl."""

import os

from ansible.plugins.filter.core import FilterModule as FilterModuleBase
from nacl import encoding, public  # pylint: disable=import-self # type: ignore[attr-defined]


class FilterModule(FilterModuleBase):
    """Ansible filter plugin to encrypt secrets for GitHub."""

    def filters(self):
        """Return the filter functions provided by this plugin."""
        return {"encrypt_secret": self.encrypt_secret}

    def encrypt_secret(self, *args, **_kwargs) -> str:
        """Encrypt a secret using the given public key."""

        secret = str(args[0])
        public_key_str = str(args[1])

        if os.path.isfile(public_key_str):
            with open(public_key_str, "r", encoding="utf-8") as pk_file:
                public_key_str = pk_file.read().strip()

        public_key_str = public_key_str.strip()
        public_key = public.PublicKey(
            public_key_str.encode("utf-8"), encoding.Base64Encoder
        )

        sealed_box = public.SealedBox(public_key)
        encrypted = sealed_box.encrypt(secret.encode("utf-8"))
        return encoding.Base64Encoder.encode(encrypted).decode("utf-8")
