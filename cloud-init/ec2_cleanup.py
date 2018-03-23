#!/usr/bin/env python3
"""Clean up all running EC2 instances, VPCs, and storage.

Copyright 2018 Canonical Ltd.
Joshua Powers <josh.powers@canonical.com>
"""
import boto3


def clean_ec2():
    """Clean up all running EC2 instances, VPCs, and storage."""
    client = boto3.client('ec2')
    resource = boto3.resource('ec2')

    print('# searching for vpc')
    vpc_tag = [{'Name': 'tag:Name', 'Values': ['cii-*']}]
    for vpc in list(resource.vpcs.filter(Filters=vpc_tag)):
        print('cleaning up vpc %s' % vpc.id)
        for instance in vpc.instances.all():
            print('terminating instance %s' % instance.id)
            instance.terminate()
            instance.wait_until_terminated()

        for security_group in vpc.security_groups.filter(Filters=vpc_tag):
            print('terminating security group %s' % security_group.id)
            security_group.delete()

        for subnet in vpc.subnets.filter(Filters=vpc_tag):
            print('terminating subnet %s' % subnet.id)
            subnet.delete()

        for route_table in vpc.route_tables.filter(Filters=vpc_tag):
            print('terminating route table %s' % route_table.id)
            route_table.delete()

        for internet_gateway in vpc.internet_gateways.filter(Filters=vpc_tag):
            print('terminating internet gateway %s' % internet_gateway.id)
            internet_gateway.detach_from_vpc(VpcId=vpc.id)
            internet_gateway.delete()

        print('terminating vpc %s' % vpc.id)
        vpc.delete()

    print('# searching for ssh keys')
    key_name = {'Name': 'key-name', 'Values': ['cii-*']}
    for key in client.describe_key_pairs(Filters=[key_name])['KeyPairs']:
        print('deleting ssh key %s' % key['KeyName'])
        client.delete_key_pair(KeyName=key['KeyName'])

    print('# searching for ami')
    for image in resource.images.filter(Owners=['self']).all():
        print('removing custom ami %s' % image.id)
        client.deregister_image(ImageId=image.id)

    print('# searching for snapshots')
    for snapshot in resource.snapshots.filter(OwnerIds=['self']).all():
        print('removing custom snapshot %s' % snapshot.id)
        client.delete_snapshot(SnapshotId=snapshot.id)


if __name__ == '__main__':
    clean_ec2()
