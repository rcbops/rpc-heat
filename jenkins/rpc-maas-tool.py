#!/usr/bin/env python

from rackspace_monitoring.drivers.rackspace import RackspaceMonitoringValidationError
from rackspace_monitoring.providers import get_driver
from rackspace_monitoring.types import Provider

import ConfigParser
import argparse
import multiprocessing
import os
import re
import sys
import time


def main(args):
    config = ConfigParser.RawConfigParser()
    config.read('/root/.raxrc')
    rpc = RpcMaasTool(args, config)

    if rpc.conn is None:
        print("Unable to get a client to MaaS, exiting")
        sys.exit(1)

    if args.command == 'alarms':
        rpc.alarms()
    elif args.command == 'check':
        rpc.check()
    elif args.command == 'delete':
        rpc.delete()
    elif args.command == 'remove-defunct-checks':
        rpc.remove_defunct_checks()
    elif args.command == 'remove-defunct-alarms':
        rpc.remove_defunct_alarms()

class RpcMaasTool(object):
    def __init__(self, args, config):
        self.args = args
        self.config = config
        self.driver = get_driver(Provider.RACKSPACE)
        self.conn = self._get_conn()


    def alarms(self):
        for entity in self._get_entities():
            alarms = self.conn.list_alarms(entity)
            print alarms
            if alarms:
                print('Entity %s (%s):' % (entity.id, entity.label))
                for alarm in alarms:
                    print ' %s' % alarm.label


    def check(self):
        error = 0
        jobs = []

        for entity in self._get_entities():
            #p = multiprocessing.Process(target=check_worker, args=(conn, entity,))
            p = multiprocessing.Process(target=self.check_worker, args=(entity,))
            jobs.append(p)
            p.start()

        for j in jobs:
            j.join(None)
            if j.exitcode != 0:
                error = j.exitcode

        sys.exit(error)


    def check_worker(self, entity):
        error = 0
        output = [entity.label]

        for check in self.conn.list_checks(entity):
            if check.type != 'agent.plugin':
                continue

            tries = 0

            while tries < 3:
                try:
                    result = self.conn.test_existing_check(check)
                    break
                except Exception as e:
                    output.append('Check %s (%s): <%s> %s' % (check.id, check.label, type(e), e))

                    ssh_opts = '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
                    service_name = 'rackspace-monitoring-agent'
                    cmd = "ssh %s %s 'stop %s; start %s' > /dev/null 2>&1" % (ssh_opts,
                                                                              entity.label,
                                                                              service_name,
                                                                              service_name)

                    output.append('Check %s (%s): Restarting rackspace-monitoring-agent service' %
                                  (check.id, check.label))
                    os.system(cmd)
                    time.sleep(5)

                    tries += 1

            if tries == 3:
                break

            available = result[0]['available']
            status = result[0]['status']

            if available is False:
                output.append('Check %s (%s) did not run correctly' %
                              (check.id, check.label))
                error = 1
            elif status not in ('okay', 'success'):
                output.append("Check %s (%s) ran correctly but returned a "
                              "'%s' status" % (check.id, check.label, status))
                error = 1
            #else:
            #    output.append("Check %s (%s) ran successfully" %
            #                  (check.id, check.label))

            time.sleep(5)

        print '\n'.join(output)

        sys.exit(error)


    def delete(self):
        count = 0

        if self.args.force is False:
            print "*** Proceeding WILL delete ALL your checks (and data) ****"
            if raw_input("Type 'from orbit' to continue: ") != 'from orbit':
                return

        for entity in self._get_entities():
            error = 0
            for check in self.conn.list_checks(entity):
                self.conn.delete_check(check)
                count += 1

        print "Number of checks deleted: %s" % count


    def remove_defunct_checks(self):
        check_count = 0

        for entity in self._get_entities():
            for check in self.conn.list_checks(entity):
                if re.match('filesystem--.*', check.label):
                    self.conn.delete_check(check)
                    check_count += 1

        print "Number of checks deleted: %s" % check_count


    def remove_defunct_alarms(self):
        alarm_count = 0
        defunct_alarms = {'rabbit_mq_container': ['disk_free_alarm', 'mem_alarm'],
                          'galera_container': ['WSREP_CLUSTER_SIZE',
                                               'WSREP_LOCAL_STATE_COMMENT']}

        for entity in self._get_entities():
            for alarm in self.conn.list_alarms(entity):
                for container in defunct_alarms:
                    for defunct_alarm in defunct_alarms[container]:
                        if re.match('%s--.*%s' % (defunct_alarm, container), alarm.label):
                            self.conn.delete_alarm(alarm)
                            alarm_count += 1

        print "Number of alarms deleted: %s" % alarm_count


    def _get_conn(self):
        conn = None

        if self.config.has_section('credentials'):
            try:
                user = self.config.get('credentials', 'username')
                api_key = self.config.get('credentials', 'api_key')
            except Exception as e:
                print e
            else:
                conn = self.driver(user, api_key)
        if not conn and self.config.has_section('api'):
            try:
                url = self.config.get('api', 'url')
                token = self.config.get('api', 'token')
            except Exception as e:
                print e
            else:
                conn = self.driver(None, None, ex_force_base_url=url,
                                   ex_force_auth_token=token)

        return conn


    def _get_entities(self):
        entities = []

        for entity in self.conn.list_entities():
            if self.args.prefix is None or self.args.prefix in entity.label:
                entities.append(entity)

        return entities


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Test MaaS checks')
    parser.add_argument('command',
                        type=str,
                        choices=['alarms', 'check', 'delete',
                                 'remove-defunct-checks',
                                 'remove-defunct-alarms'],
                        help='Command to execute')
    parser.add_argument('--force',
                        action="store_true",
                        help='Do stuff irrespective of consequence'),
    parser.add_argument('--prefix',
                        type=str,
                        help='Limit testing to checks on entities labelled w/ '
                             'this prefix',
                        default=None)
    args = parser.parse_args()

    main(args)
