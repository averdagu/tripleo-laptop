#!/usr/bin/env bash

source ~/stackrc

if [[ ! -d ~/templates ]]; then
    ln -s /usr/share/openstack-tripleo-heat-templates templates
fi
if [[ ! -d ~/tht ]]; then
    ln -s tripleo-laptop/tht
fi

for IP in $(grep 192.168.24 tht/ctlplane-assignments.yaml | grep -v 192.168.24.1 | awk {'print $3'}); do
    if [[ $(ssh heat-admin@$IP "hostname") ]]; then
	echo "ssh heat-admin@$IP is working";
    else
	echo "ssh heat-admin@$IP is NOT working. Aborting.";
	exit 1
    fi
done

time openstack overcloud deploy --templates ~/templates \
     -r ~/tht/all_in_one.yaml \
     -e ~/templates/environments/low-memory-usage.yaml \
     -e ~/templates/environments/disable-telemetry.yaml \
     -e ~/templates/environments/deployed-server-environment.yaml \
     -e ~/templates/environments/docker.yaml \
     -e ~/docker_registry.yaml \
     -e ~/templates/environments/deployed-server-bootstrap-environment-centos.yaml \
     -e ~/tht/ctlplane-assignments.yaml \
     --disable-validations
