#!/usr/bin/env python
# filename: check_my_jinja_recursive.py
import sys
import os
import argparse
from jinja2 import Environment, FileSystemLoader

args = argparse.ArgumentParser(description="Check Jinja2 templates for syntax errors recursively.")
args.add_argument('path', type=str, default='.', help='Path to the directory containing Jinja2 templates.')
parsed_args = args.parse_args()
      
def check_directory(path):
    for root, dirs, files in os.walk(path):
        for file in files:
            if file.endswith('.j2'):
                print(f"Found Jinja2 template: {os.path.join(root, file)}")
                yield os.path.join(root, file)
        for dir in dirs:
            yield from check_directory(os.path.join(root, dir))

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
    except Exception as e:
        print(f"Error in template '{template_path}': {e}")
        sys.exit(1)