#!/usr/bin/env python3
"""Render the real vendored SDK and evaluate its effective Secret permissions."""
import base64
import subprocess
import unittest
from pathlib import Path

import yaml

CHART = Path(__file__).resolve().parents[1]


def render():
    return list(yaml.safe_load_all(subprocess.check_output([
        'helm', 'template', 'composio', str(CHART), '--namespace', 'composio',
        '-f', str(CHART / 'values-managed-vpc.yaml'),
        '--set', 'global.disableK8SecretCheck=true',
    ], text=True)))


def allows(rules, verb, name):
    return any(('' in r.get('apiGroups', []) or '*' in r.get('apiGroups', []))
               and ('secrets' in r.get('resources', []) or '*' in r.get('resources', []))
               and (verb in r.get('verbs', []) or '*' in r.get('verbs', []))
               and (not r.get('resourceNames') or name in r['resourceNames']) for r in rules)


class ManagedVpcSdkRbac(unittest.TestCase):
    def test_sdk_cannot_read_application_or_helm_secrets(self):
        docs = [d for d in render() if d]
        deployment = next(d for d in docs if d['kind'] == 'Deployment' and d['metadata']['name'] == 'replicated')
        account = deployment['spec']['template']['spec']['serviceAccountName']
        bindings = [d for d in docs if d['kind'] in ('RoleBinding', 'ClusterRoleBinding')
                    and any(s.get('kind') == 'ServiceAccount' and s['name'] == account for s in d['subjects'])]
        self.assertTrue(bindings)
        rules = []
        for binding in bindings:
            self.assertEqual(binding['kind'], 'RoleBinding')
            self.assertEqual(binding['roleRef']['kind'], 'Role')
            role = next(d for d in docs if d['kind'] == 'Role' and d['metadata']['name'] == binding['roleRef']['name'])
            rules.extend(role['rules'])
        for name in ('composio-runtime', 'composio-apollo-migrations', 'composio-runner-registry',
                     'sh.helm.release.v1.composio.v1', 'customer-secret'):
            for verb in ('get', 'list', 'watch', 'update', 'patch', 'delete'):
                self.assertFalse(allows(rules, verb, name), (verb, name))
        self.assertTrue(allows(rules, 'get', 'replicated'))
        self.assertTrue(allows(rules, 'update', 'replicated-instance-report'))
        self.assertTrue(any('deployments' in r.get('resources', []) and 'watch' in r.get('verbs', []) for r in rules))
        # Explicit informers, rather than Helm-secret discovery, drive application status.
        config = next(d for d in docs if d['kind'] == 'Secret' and d['metadata']['name'] == 'replicated')
        content = config.get('stringData', {}).get('config.yaml') or base64.b64decode(config['data']['config.yaml']).decode()
        self.assertIn('deployment/composio-apollo', content)
        self.assertIn('deployment/composio-thermos', content)


if __name__ == '__main__':
    unittest.main()
