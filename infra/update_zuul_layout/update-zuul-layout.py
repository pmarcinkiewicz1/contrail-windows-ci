import urllib.request
import json
import sys
import re
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("layout_file", type=str, help="Path to zuul layout file")
args = parser.parse_args()

print("Update Zuul layout file with NOOPs for unused projects - starting...")

layout_file = args.layout_file
gerrit_server = "review.opencontrail.org"
special_delimiter_line = \
        "# AUTOMATICALLY GENERATED NOOPs BELOW - DO NOT MODIFY THESE LINES MANUALLY"
template = """
  - name: {}
    template:
      - name: ci-contrail-windows-other-projects-template"""

# Responses from gerrit API are correct JSON with one exception:
special_gerrit_tag = ")]}'"

# TODO: list of actually used projects may be fetched from layout file.
actually_used_projects = [
    "Juniper/contrail-api-client",
    "Juniper/contrail-controller",
    "Juniper/contrail-vrouter",
    "Juniper/contrail-build",
    "Juniper/contrail-third-party",
    "Juniper/contrail-common",
    "Juniper/contrail-windows-docker-driver",
    "Juniper/contrail-windows",
]

projects = []
lines_to_preserve = []
relevant_project_name_re = re.compile("(Juniper|tungstenfabric)/.*")

print("> Reading original layout file...")

with open(layout_file, "r") as original_layout_yaml:
    lines_to_preserve = original_layout_yaml.read().splitlines()

delimiter_index = -1
for index, line in enumerate(lines_to_preserve):
    if line == special_delimiter_line:
        delimiter_index = index
        break

if delimiter_index > -1:
    if len(lines_to_preserve) > delimiter_index + 1:
        del lines_to_preserve[delimiter_index + 1:]
else:
    lines_to_preserve.append("")
    lines_to_preserve.append(special_delimiter_line)

print("> Fetching list of projects from Gerrit...")

with urllib.request.urlopen(\
        "http://{}/projects/".format(gerrit_server)) as response:
    text_with_json = response.read().decode(\
            response.headers.get_content_charset())
    text_with_json = text_with_json[text_with_json.find(special_gerrit_tag) \
            + len(special_gerrit_tag):]
    projects = json.loads(text_with_json)

print("> Updating layout file...")

with open(layout_file, "w", newline="\n") as new_layout_file:
    for line in lines_to_preserve:
        print(line, file=new_layout_file)

    for project_name, _ in sorted(projects.items()):
        if not project_name in actually_used_projects \
                and relevant_project_name_re.match(project_name):
            print(template.format(project_name), file=new_layout_file)

print("> Done!")
sys.exit(0)
