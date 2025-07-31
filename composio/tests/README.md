# Helm Unit Tests for Composio Chart

This directory contains comprehensive unit tests for the Composio Helm chart using the [helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin.

## 📋 Prerequisites

### Install helm unittest plugin

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

Or using our test runner (which will auto-install the plugin):

```bash
./run-tests.sh
```

## 🏗️ Test Structure

### Test Files

| Test File | Description | Templates Covered |
|-----------|-------------|-------------------|
| `apollo_test.yaml` | Apollo service deployment and service tests | `apollo.yaml` |
| `mercury_test.yaml` | Mercury service with conditional logic | `mercury.yaml`, `mercury-service.yaml` |
| `mcp_test.yaml` | MCP service deployment and service tests | `mcp.yaml` |
| `thermos_test.yaml` | Thermos service deployment and service tests | `thermos.yaml` |
| `minio_test.yaml` | Minio storage deployment, service, and PVC tests | `minio.yaml` |
| `knative_test.yaml` | Knative serving and CRD tests | `knative-serving.yaml`, `knative-crds.yaml` |
| `db_init_test.yaml` | Database initialization job tests | `db-init-job.yaml` |
| `ecr_secret_test.yaml` | ECR authentication secret tests | `ecr-secret.yaml` |
| `ingress_test.yaml` | Mercury ingress configuration tests | `mercury-ingress.yaml` |
| `helpers_test.yaml` | Helper template function tests | `_helpers.tpl` |

### Test Values

- `test-values.yaml` - Test-specific values for consistent testing

## 🚀 Running Tests

### Using the Test Runner (Recommended)

```bash
# Make the script executable
chmod +x run-tests.sh

# Run all tests
./run-tests.sh

# Run specific component tests
./run-tests.sh apollo
./run-tests.sh mercury
./run-tests.sh mcp
./run-tests.sh thermos
./run-tests.sh minio
./run-tests.sh knative
./run-tests.sh helpers
./run-tests.sh secrets
./run-tests.sh db
./run-tests.sh ingress

# Run with verbose output
./run-tests.sh verbose

# Run with debug output
./run-tests.sh debug

# Run including subcharts
./run-tests.sh with-subchart
```

### Using helm unittest directly

```bash
# Run all tests
helm unittest . -f 'tests/*_test.yaml'

# Run specific test file
helm unittest . -f 'tests/apollo_test.yaml'

# Run with verbose output
helm unittest . -f 'tests/*_test.yaml' -v

# Run with custom values
helm unittest . -f 'tests/*_test.yaml' --values tests/test-values.yaml
```

## 🧪 Test Coverage

### Apollo Service Tests
- ✅ Deployment creation and configuration
- ✅ Service creation and port configuration
- ✅ Image configuration and pull policies
- ✅ Resource limits and requests
- ✅ Health check probes
- ✅ Rolling update strategy
- ✅ Image pull secrets

### Mercury Service Tests
- ✅ Conditional deployment creation (enabled/disabled, knative/regular)
- ✅ Image configuration with default fallbacks
- ✅ Environment variables
- ✅ Security context
- ✅ Service configuration
- ✅ Port configuration with defaults

### MCP Service Tests
- ✅ Deployment and service creation
- ✅ Replica count configuration
- ✅ Image and resource configuration
- ✅ Port and service type configuration

### Thermos Service Tests
- ✅ Deployment and service creation
- ✅ Rolling update strategy
- ✅ Resource configuration
- ✅ Image pull secrets

### Minio Tests
- ✅ Deployment, service, and PVC creation
- ✅ Authentication configuration
- ✅ Health probes
- ✅ Persistence configuration
- ✅ Resource limits

### Knative Tests
- ✅ Conditional Knative service creation
- ✅ Scaling configuration
- ✅ Timeout and concurrency settings
- ✅ Custom Resource Definitions
- ✅ Security context

### Database Init Tests
- ✅ Job creation and configuration
- ✅ Environment variables from secrets
- ✅ Restart policy and backoff limits
- ✅ Completion settings

### ECR Secret Tests
- ✅ Conditional secret creation
- ✅ Docker config JSON generation
- ✅ Namespace configuration

### Ingress Tests
- ✅ Conditional ingress creation
- ✅ Host and TLS configuration
- ✅ Annotations support
- ✅ Backend service configuration

### Helper Function Tests
- ✅ Name generation functions
- ✅ Label generation functions
- ✅ Namespace helper functions
- ✅ Name override functionality

## 🔧 Test Patterns and Conventions

### Test Structure
Each test file follows this structure:
```yaml
suite: descriptive test suite name
templates:
  - template-file.yaml
tests:
  - it: should do something specific
    set:
      key: value
    asserts:
      - assertion_type:
          path: jsonpath
          value: expected_value
```

### Common Assertions Used
- `isKind`: Verifies Kubernetes resource type
- `equal`: Checks exact value match
- `contains`: Checks if array/object contains value
- `isNotEmpty`: Verifies field is not empty
- `hasDocuments`: Verifies document count (for conditional resources)
- `matchRegex`: Pattern matching

### Test Data Management
- Use `set:` block to override values for specific tests
- Use `test-values.yaml` for consistent test data
- Test both default values and custom configurations

## 🎯 Best Practices

### Writing New Tests
1. **Test both positive and negative scenarios**
   - Verify resources are created when they should be
   - Verify resources are NOT created when they shouldn't be

2. **Test conditional logic thoroughly**
   - Use `hasDocuments: count: 0` for disabled features
   - Test all conditional branches

3. **Validate critical configurations**
   - Security contexts
   - Resource limits
   - Health checks
   - Environment variables

4. **Use descriptive test names**
   - Start with "should" 
   - Be specific about what you're testing

### Example Test Case
```yaml
- it: should create deployment with correct image when custom values provided
  set:
    apollo.image.repository: custom-repo
    apollo.image.tag: v2.0.0
    apollo.image.pullPolicy: Never
  asserts:
    - isKind:
        of: Deployment
    - equal:
        path: spec.template.spec.containers[0].image
        value: custom-repo:v2.0.0
    - equal:
        path: spec.template.spec.containers[0].imagePullPolicy
        value: Never
```

## 🐛 Debugging Tests

### Common Issues and Solutions

1. **Test fails with "template not found"**
   - Ensure template file exists in templates/ directory
   - Check template name in test file matches actual filename

2. **JSONPath assertion fails**
   - Use `helm unittest . -f 'tests/test_file.yaml' -v` for verbose output
   - Check the actual rendered YAML structure
   - Verify JSONPath syntax (arrays use [0], objects use .key)

3. **Conditional tests not working**
   - Ensure you're setting the right conditions in the `set:` block
   - Use `hasDocuments: count: 0` for templates that shouldn't render

4. **Value interpolation issues**
   - Check if you need to set dependencies (e.g., global values)
   - Verify value path matches exactly with values.yaml structure

### Debug Commands
```bash
# Verbose output to see rendered templates
helm unittest . -f 'tests/apollo_test.yaml' -v

# Debug mode for more details
helm unittest . -f 'tests/apollo_test.yaml' --debug

# Test with specific values file
helm unittest . -f 'tests/apollo_test.yaml' --values tests/test-values.yaml -v
```

## 📊 Test Metrics

Run tests to see coverage metrics:
```bash
./run-tests.sh verbose
```

The test suite covers:
- 🔹 **12+ templates** with comprehensive test coverage
- 🔹 **100+ test cases** covering various scenarios
- 🔹 **Conditional logic** for all feature flags
- 🔹 **Security configurations** and best practices
- 🔹 **Resource management** and limits
- 🔹 **Service discovery** and networking
- 🔹 **Storage and persistence** configurations

## 🤝 Contributing

When adding new templates or modifying existing ones:

1. **Add corresponding tests** in the appropriate test file
2. **Test both default and custom configurations**
3. **Include negative test cases** for conditional logic
4. **Update this README** if adding new test files
5. **Run the full test suite** before submitting changes

```bash
# Always run full test suite before committing
./run-tests.sh all
```

## 📚 Resources

- [helm-unittest Documentation](https://github.com/helm-unittest/helm-unittest)
- [Helm Testing Guide](https://helm.sh/docs/topics/chart_tests/)
- [JSONPath Online Evaluator](https://jsonpath.com/) - For debugging JSONPath expressions 