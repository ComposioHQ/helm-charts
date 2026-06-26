# Composio Compute Requirements

This document outlines the resource requirements (CPU and Memory) for all Composio application components.


## Quick Reference Table

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| **Redis** | 2 cores | 2 cores | 4 GiB | 4 GiB |
| **Apollo** | 1 core | 1 core | 5 GiB | 6 GiB |
| **Apollo DB-Init** | 1 core | 1 core | 5 GiB | 6 GiB |
| **Thermos** | 2 cores | 2 cores | 4 GiB | 5 GiB |
| **Thermos DB-Init** | 2 cores | 2 cores | 4 GiB | 5 GiB |
| **Mercury** | 1 core | 2 cores | 2 GiB | 4 GiB |
| **Frontend** | 1 core | 1 core | 2 GiB | 3 GiB |
| **Weaviate** | 1 core | 2 cores | 2 GiB | 4 GiB |
| **TOTAL** | **11 cores** | **13 cores** | **28 GiB** | **37 GiB** |

### Summary

- **Minimum CPU Required**: 11 cores (requests)
- **Maximum CPU Required**: 13 cores (limits)
- **Minimum Memory Required**: 28 GiB (requests)
- **Maximum Memory Required**: 37 GiB (limits)

---

## Total Resource Requirements

These are the guaranteed resources that Kubernetes will reserve for your deployment:

- **Total CPU**: 11 cores
- **Total Memory**: 28 GiB
---

## Detailed Resource Specifications

### Internal Redis

Redis is used for caching and session management.

**Resource Configuration:**
- **CPU Request**: 2 cores
- **CPU Limit**: 2 cores
- **Memory Request**: 4 GiB
- **Memory Limit**: 4 GiB

```yaml
redis:
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "4Gi"
      cpu: "2"
```

---

### Apollo

Apollo is the main application service.

**Resource Configuration:**
- **CPU Request**: 1 core
- **CPU Limit**: 1 core
- **Memory Request**: 5 GiB
- **Memory Limit**: 6 GiB

```yaml
apollo:
  resources:
    requests:
      memory: "5Gi"
      cpu: "1"
    limits:
      memory: "6Gi"
      cpu: "1"
```

---

### Apollo DB-Init

Database initialization job for Apollo.

**Resource Configuration:**
- **CPU Request**: 1 core
- **CPU Limit**: 1 core
- **Memory Request**: 5 GiB
- **Memory Limit**: 6 GiB

```yaml
apollo-db-init:
  resources:
    requests:
      memory: "5Gi"
      cpu: "1"
    limits:
      memory: "6Gi"
      cpu: "1"
```

---

### Thermos

Thermos handles background processing and job execution.

**Resource Configuration:**
- **CPU Request**: 2 cores
- **CPU Limit**: 2 cores
- **Memory Request**: 4 GiB
- **Memory Limit**: 5 GiB

```yaml
thermos:
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "5Gi"
      cpu: "2"
```

---

### Thermos DB-Init

Database initialization job for Thermos.

**Resource Configuration:**
- **CPU Request**: 2 cores
- **CPU Limit**: 2 cores
- **Memory Request**: 4 GiB
- **Memory Limit**: 5 GiB

```yaml
thermos-db-init:
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "5Gi"
      cpu: "2"
```

---

### Mercury

Mercury manages API integrations and external communications.

**Resource Configuration:**
- **CPU Request**: 1 core
- **CPU Limit**: 2 cores
- **Memory Request**: 2 GiB
- **Memory Limit**: 4 GiB

```yaml
mercury:
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"
```

---

### Frontend Application

The user-facing frontend application.

**Resource Configuration:**
- **CPU Request**: 1 core
- **CPU Limit**: 1 core
- **Memory Request**: 2 GiB
- **Memory Limit**: 3 GiB

```yaml
frontend:
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "3Gi"
      cpu: "1"
```

---

### Weaviate

**Resource Configuration:**
- **CPU Request**: 1 core
- **CPU Limit**: 2 cores
- **Memory Request**: 2 GiB
- **Memory Limit**: 4 GiB

```yaml
weaviate:
  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"
```
