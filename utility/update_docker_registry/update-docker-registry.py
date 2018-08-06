#!/usr/bin/env python

import sys
import subprocess

IMAGES = [
    'contrail-node-init',
    'contrail-nodemgr',
    'contrail-controller-config-api',
    'contrail-controller-config-svcmonitor',
    'contrail-controller-config-schema',
    'contrail-controller-config-devicemgr',
    'contrail-vrouter-kernel-init-dpdk',
    'contrail-vrouter-kernel-init',
    'contrail-vrouter-agent-dpdk',
    'contrail-vrouter-agent',
    'contrail-controller-control-control',
    'contrail-controller-control-named',
    'contrail-controller-control-dns',
    'contrail-controller-webui-web',
    'contrail-controller-webui-job',
    'contrail-analytics-api',
    'contrail-analytics-collector',
    'contrail-analytics-query-engine',
    'contrail-analytics-alarm-gen',
    'contrail-analytics-snmp-collector',
    'contrail-analytics-topology',
    'contrail-external-cassandra',
    'contrail-external-zookeeper',
    'contrail-external-rabbitmq',
    'contrail-external-kafka',
    'contrail-openstack-neutron-init',
    'contrail-openstack-compute-init',
    'contrail-openstack-ironic-notification-manager',
    'contrail-openstack-heat-init',
]

REMOTE_REPO_URL = 'docker.io/opencontrailnightly'
LOCAL_REPO_URL = 'localhost:5000'

def get_image_url(repo, image, version):
    return '{}/{}:{}'.format(repo, image, version)

def pull_image(image, version):
    image_url = get_image_url(REMOTE_REPO_URL, image, version)
    subprocess.check_call(['docker', 'image', 'pull', image_url])

def get_image_id(image, version):
    output = subprocess.check_output(['docker', 'image', 'ls'])
    for line in output.splitlines():
        entries = line.split()
        if image in entries[0] and REMOTE_REPO_URL in entries[0] and entries[1] == version:
            return entries[2]

def tag_image(image, version, image_id):
    image_url = get_image_url(LOCAL_REPO_URL, image, version)
    subprocess.check_call(['docker', 'tag', image_id, image_url])

def push_image(image, version):
    image_url = get_image_url(LOCAL_REPO_URL, image, version)
    subprocess.check_call(['docker', 'push', image_url])

def main():
    if len(sys.argv) != 2:
        print('Usage: {} <CONTRAIL-VERSION-TAG>'.format(sys.argv[0]))
        exit(1)

    version_tag = sys.argv[1]

    for image in IMAGES:
        pull_image(image, version_tag)
        image_id = get_image_id(image, version_tag)
        tag_image(image, version_tag, image_id)
        push_image(image, version_tag)

if __name__ == '__main__':
    main()
