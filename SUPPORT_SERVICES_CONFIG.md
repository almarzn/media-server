# FlareSolverr and Byparr Configuration Guide

## Overview

This document provides configuration instructions for integrating FlareSolverr and Byparr support services with Prowlarr in the Kubernetes media server deployment.

## Service Endpoints

- **FlareSolverr**: `http://media-server-flaresolverr:8191`
- **Byparr**: `http://media-server-byparr:8191`

## FlareSolverr Configuration

### Purpose
FlareSolverr bypasses Cloudflare protection for indexers that implement anti-bot measures.

### Configuration in Prowlarr
1. Navigate to **Settings** → **Indexers** in Prowlarr web interface
2. Scroll down to **FlareSolverr** section
3. Configure the following settings:
   - **Host**: `http://media-server-flaresolverr:8191`
   - **Max Timeout**: `60000` (60 seconds)
   - **Test**: Click to verify connectivity

### Supported Features
- Cloudflare challenge solving
- JavaScript execution
- Cookie handling
- User agent spoofing
- Automatic retry mechanisms

### Testing FlareSolverr
```bash
# Test basic connectivity
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -n media-server -- \
  curl -s http://media-server-flaresolverr:8191/

# Test API functionality
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -n media-server -- \
  curl -s -X POST http://media-server-flaresolverr:8191/v1 \
  -H "Content-Type: application/json" \
  -d '{"cmd": "request.get", "url": "https://httpbin.org/get", "maxTimeout": 60000}'
```

## Byparr Configuration

### Purpose
Byparr provides additional content discovery capabilities and enhanced search functionality.

### Configuration in Prowlarr
1. Navigate to **Settings** → **Applications** in Prowlarr web interface
2. Add new application with the following settings:
   - **Name**: Byparr
   - **Sync Level**: Full Sync
   - **Server**: `http://media-server-byparr:8191`
   - **API Key**: (Generate from Byparr interface if required)

### API Documentation
Byparr provides a Swagger UI interface accessible at:
`http://media-server-byparr:8191/docs`

### Testing Byparr
```bash
# Test basic connectivity
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -n media-server -- \
  curl -s -o /dev/null -w "%{http_code}" http://media-server-byparr:8191/

# Test API documentation endpoint
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -n media-server -- \
  curl -s -o /dev/null -w "%{http_code}" http://media-server-byparr:8191/docs
```

## Integration Workflow

### FlareSolverr Integration
1. **Indexer Configuration**: When adding indexers that use Cloudflare protection
2. **Automatic Detection**: Prowlarr automatically uses FlareSolverr when configured
3. **Challenge Solving**: FlareSolverr handles JavaScript challenges transparently
4. **Result Forwarding**: Solved responses are returned to Prowlarr

### Byparr Integration
1. **Content Discovery**: Byparr enhances search capabilities across multiple sources
2. **API Integration**: Provides RESTful API for content queries
3. **Enhanced Metadata**: Additional content information and recommendations
4. **Search Optimization**: Improved search algorithms and result ranking

## Troubleshooting

### FlareSolverr Issues
- **Connection Timeout**: Increase maxTimeout value in Prowlarr settings
- **Challenge Failures**: Check FlareSolverr logs for specific error messages
- **Performance Issues**: Monitor resource usage and adjust limits if needed

### Byparr Issues
- **API Errors**: Verify service is running and accessible
- **Configuration Problems**: Check API key and endpoint configuration
- **Search Failures**: Review Byparr logs for detailed error information

### Common Commands
```bash
# Check service status
kubectl get pods -n media-server -l app.kubernetes.io/component=flaresolverr
kubectl get pods -n media-server -l app.kubernetes.io/component=byparr

# View service logs
kubectl logs -n media-server deployment/media-server-flaresolverr
kubectl logs -n media-server deployment/media-server-byparr

# Test connectivity from Prowlarr
kubectl exec -n media-server deployment/media-server-prowlarr -c prowlarr -- \
  wget -qO- http://media-server-flaresolverr:8191/
```

## Security Considerations

- Both services run with restricted security contexts
- Network access is limited to cluster-internal communication
- No external ports are exposed directly
- All communication occurs over HTTP within the cluster

## Resource Usage

### FlareSolverr
- **CPU Request**: 50m
- **Memory Request**: 128Mi
- **CPU Limit**: 200m
- **Memory Limit**: 512Mi

### Byparr
- **CPU Request**: 25m
- **Memory Request**: 64Mi
- **CPU Limit**: 100m
- **Memory Limit**: 256Mi

## Maintenance

Both services are managed through the Helm chart and will be automatically updated when new image versions are available through FluxCD image automation.

To manually restart services:
```bash
kubectl rollout restart deployment/media-server-flaresolverr -n media-server
kubectl rollout restart deployment/media-server-byparr -n media-server
```