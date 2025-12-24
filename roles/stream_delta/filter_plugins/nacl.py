from base64 import b64encode
from nacl import encoding, public
import os

from jinja2 import TemplateSyntaxError
from jinja2 import Environment, FileSystemLoader
from ansible.plugins.filter.core import FilterModule



class FilterModule(FilterModule):
    """Ansible filter plugin to encrypt secrets for GitHub."""

    def filters(self):
        return {
            'encrypt_secret': self.encrypt_secret
        }

    def encrypt_secret(self, *args, **kwargs) -> str:
        """Encrypt a secret using the given public key."""
        
        secret = str(args[0])
        public_key_str = str(args[1])
    
        if os.path.isfile(public_key_str):
            with open(public_key_str, 'r') as pk_file:
                public_key_str = pk_file.read().strip()
                
        public_key_str = public_key_str.strip()
        public_key = public.PublicKey(public_key_str.encode("utf-8"), encoding.Base64Encoder)
        
        sealed_box = public.SealedBox(public_key)
        encrypted = sealed_box.encrypt(secret.encode("utf-8"))
        return encoding.Base64Encoder.encode(encrypted).decode("utf-8")