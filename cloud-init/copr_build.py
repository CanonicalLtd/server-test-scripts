#!/usr/bin/env python3
"""Create cloud-init srpm build via COPR.

https://copr.fedorainfracloud.org/coprs/g/cloud-init/

Copyright 2017 Canonical Ltd.
Joshua Powers <josh.powers@canonical.com>
"""
import argparse
import datetime
import os
import sys
import time

import copr

URL_COPR = "https://copr.fedorainfracloud.org/coprs/g/cloud-init"
PROJECT_OWNER = "@cloud-init"
DEFAULT_PROJECT = "cloud-init"

DEFAULT_COPR_CONF = os.path.expanduser('~/.config/copr')


def check_test_chroot(tasks):
    """Checks the status of specific chroots for testing."""
    print('\nChecking status of test chroot(s):\n')
    for chroot in ARGS.test_chroots:
        if chroot not in tasks:
            raise Exception('chroot {} unexpectedly not in tasks ({})'.format(
                chroot, tasks.keys()))
        print('%24s: %s' % (chroot, tasks[chroot]))
        if tasks[chroot] != 'succeeded':
            print('Build failed!')
            sys.exit(1)


def check_build_status(build, tasks):
    """Check status of builds in each chroot."""
    tasks_watched = set(tasks.keys())
    tasks_done = set()

    print('\nChecking stauts of build(s):\n')
    while tasks_watched != tasks_done:
        for task in build.get_build_tasks():
            name = task.chroot_name
            state_cur = task.state
            state_previous = tasks[name]

            if name in tasks_done:
                continue

            if state_cur in ["skipped", "failed", "succeeded"]:
                tasks_done.add(name)

            if state_previous != state_cur:
                tasks[name] = state_cur
                print("%24s: %s --> %s" % (name, state_previous, state_cur))

        time.sleep(10)


def get_build_tasks(build):
    """Get build tasks."""
    tasks = {}
    for chroot in build.get_build_tasks():
        tasks[chroot.chroot_name] = 'importing'

    print('\nBuilding in the following chroot(s):\n')
    for key in sorted(tasks):
        print('     * %s' % key)

    return tasks


def launch_build(project, srpm):
    """Launch a build from given srpm."""
    build = project.create_build_from_file(srpm, enable_net=False)

    print('Started COPR build on %s (ID: %s)' % (project.name, build.id))
    print('%s/%s/build/%s' % (URL_COPR, project.name, build.id))

    return build


def mention_expiration_on_creds(conf_file):
    exp_lines = []
    print("******** Copr API creds in '%s' *do* expire ********" % conf_file)
    print("******** Get new creds at %s ********" %
          "https://copr.fedorainfracloud.org/api/")
    try:
        with open(conf_file, "r") as fp:
            contents = fp.read()
        exp_lines = [l for l in contents.splitlines()
                     if 'expiration' in l]
    except FileNotFoundError:
        print("Did not find creds file: %s" % (conf_file,))

    if exp_lines:
        print("From your config:")
        print(''.join(["  %s\n" % l for l in exp_lines]))


def main(srpm, copr_conf=DEFAULT_COPR_CONF, project_name=DEFAULT_PROJECT):
    """Query COPR info."""
    if not os.path.isfile(srpm):
        print("Error: The given SRPM is not a file:\n%s" % srpm)
        sys.exit(1)

    client = copr.create_client2_from_file_config(copr_conf)

    project = client.projects.get_list(
        owner=PROJECT_OWNER,
        name=project_name
    )

    if not project:
        print("Project not found: %s/%s" % (PROJECT_OWNER, project_name))
        sys.exit(1)

    project = project[0]

    print(datetime.datetime.now())
    try:
        build = launch_build(project, srpm)
    except Exception as e:
        mention_expiration_on_creds(copr_conf)
        raise e

    # 2018-03-05: adding sleep to let builds ramp up
    # this after a {'state': ['Not a valid choice.']} exception
    reps = 6
    for naptime in [5]*reps + [10]*reps + [30]*reps:
        time.sleep(naptime)
        tasks = get_build_tasks(build)
        if tasks:
            break

    check_build_status(build, tasks)
    check_test_chroot(tasks)
    print()
    print(datetime.datetime.now())


if __name__ == '__main__':
    ARGPARSER = argparse.ArgumentParser(
        description='cloud-init copr script',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    ARGPARSER.add_argument('-c', '--config', dest='copr_conf', action='store',
                           help='copr config file location',
                           default=DEFAULT_COPR_CONF)
    ARGPARSER.add_argument('-s', '--srpm', dest='srpm', action='store',
                           required=True, help='srpm file')
    ARGPARSER.add_argument('-p', '--project', action='store',
                           default=DEFAULT_PROJECT, help='copr project name')
    ARGPARSER.add_argument('-t', '--test-chroot', action='append',
                           dest="test_chroots", metavar="CHROOT", default=[],
                           help="verify that the build succeeded in %(metavar)s.")
    ARGS = ARGPARSER.parse_args()

    main(ARGS.srpm, ARGS.copr_conf, ARGS.project)
