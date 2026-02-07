#!/usr/bin/env python
# filename: check_my_jinja_recursive.py
"""Check Jinja2 templates for syntax errors recursively in a given directory."""
import argparse
import os
import sys

from jinja2 import Environment, FileSystemLoader
from jinja2.exceptions import TemplateSyntaxError, TemplateError

args = argparse.ArgumentParser(
    description="Check Jinja2 templates for syntax errors recursively."
)
args.add_argument(
    "path",
    type=str,
    default=".",
    help="Path to the directory containing Jinja2 templates.",
)
parsed_args = args.parse_args()


def check_directory(path):
    """ Check a directory for Jinja2 templates and yield their paths. """
    for root, dirs, files in os.walk(path):
        for file in files:
            if file.endswith(".j2"):
                print(f"Found Jinja2 template: {os.path.join(root, file)}")
                yield os.path.join(root, file)
        for this_dir in dirs:
            yield from check_directory(os.path.join(root, this_dir))


# env = Environment(loader=FileSystemLoader('.'))
# templates = [x for x in env.list_templates() if x.endswith('.j2')]
# for template in templates:
#     t = env.get_template(template)
#     env.parse(t)

print("Checking Jinja2 templates in the current directory and subdirectories...")
env = Environment(loader=FileSystemLoader(parsed_args.path))
for template_path in check_directory(parsed_args.path):
    print(f"Checking template: {template_path}")
    try:
        template = env.get_template(template_path)
        env.parse(template.render())
        print(f"Template '{template_path}' is valid.")
    except (TemplateSyntaxError, TemplateError) as e:
        print(f"Error in template '{template_path}': {e}")
        sys.exit(1)
