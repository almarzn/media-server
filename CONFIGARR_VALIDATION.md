# Configarr Configuration Validation

## Static Validation (Without Running Cluster)

### 1. YAML Syntax Check
```bash
# Validate YAML syntax
helm template media-server charts/media-server --values charts/media-server/values.yaml | kubectl apply --dry-run=client -f -
```

### 2. Template Rendering Check
```bash
# Check if templates render correctly
helm template media-server charts/media-server --values charts/media-server/values.yaml > rendered-manifests.yaml
```

### 3. Configuration Structure Validation
The current Configarr config follows the correct structure:
- ✅ `trashGuideUrl` and `recyclarrConfigUrl` are set
- ✅ `sonarr.series` section with proper base_url and api_key
- ✅ `quality_definition.type: series` for TV shows
- ✅ Template includes for v4 profiles and custom formats
- ✅ Custom formats with proper scoring

## K3s Troubleshooting

### Check K3s Status
```bash
# Check if k3s service is running
sudo systemctl status k3s

# Check k3s logs
sudo journalctl -u k3s -f

# Check if k3s process is running
ps aux | grep k3s
```

### Common K3s Issues

1. **Port Conflicts**
```bash
# Check if port 6443 is in use
sudo netstat -tlnp | grep 6443
```

2. **Disk Space**
```bash
# Check available disk space
df -h
```

3. **Memory Issues**
```bash
# Check available memory
free -h
```

4. **Network Issues**
```bash
# Check if flannel is working
ip addr show flannel.1
```

### K3s Restart Commands
```bash
# Stop k3s
sudo systemctl stop k3s

# Clean up (if needed)
sudo k3s-uninstall.sh

# Reinstall k3s
curl -sfL https://get.k3s.io | sh -

# Or restart existing installation
sudo systemctl start k3s
sudo systemctl enable k3s
```

## Testing Configarr Once K3s is Running

### 1. Deploy Test Environment
```bash
# Create namespace
kubectl apply -f apps/media-server/namespace.yaml

# Deploy minimal test (just configarr components)
helm template media-server charts/media-server \
  --set sonarr.enabled=false \
  --set radarr.enabled=false \
  --set prowlarr.enabled=false \
  --set configarr.enabled=true \
  | kubectl apply -f -
```

### 2. Test ConfigMap Creation
```bash
# Check if configmap is created correctly
kubectl get configmap -n media-server
kubectl describe configmap media-server-configarr-config -n media-server
```

### 3. Validate Configuration Content
```bash
# Extract and validate config.yml
kubectl get configmap media-server-configarr-config -n media-server -o jsonpath='{.data.config\.yml}' > test-config.yml

# Check YAML syntax
python -c "import yaml; yaml.safe_load(open('test-config.yml'))"
```

### 4. Test CronJob Creation
```bash
# Check if cronjob is created
kubectl get cronjob -n media-server
kubectl describe cronjob media-server-configarr -n media-server
```

### 5. Manual Job Trigger (for testing)
```bash
# Create a manual job from the cronjob
kubectl create job --from=cronjob/media-server-configarr manual-configarr-test -n media-server

# Check job status
kubectl get jobs -n media-server
kubectl logs job/manual-configarr-test -n media-server
```

## Expected Validation Results

### Successful ConfigMap
- Should contain valid YAML with sonarr, radarr, and prowlarr sections
- Base URLs should resolve to correct service names
- API key references should use `!secret` syntax

### Successful CronJob
- Should be scheduled for hourly execution
- Should have proper volume mounts for config and secrets
- Should have resource limits defined

### Successful Manual Test
- Job should start without errors
- Should attempt to connect to services (may fail if services not running)
- Should show configuration parsing without YAML errors

## Next Steps After K3s is Fixed

1. **Start with minimal deployment** (just PostgreSQL and one service)
2. **Test Configarr with mock/placeholder API keys**
3. **Gradually add services** (Sonarr, then Radarr, then Prowlarr)
4. **Update real API keys** once services generate them
5. **Verify configuration application** in service web interfaces