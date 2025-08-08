# Configarr Implementation Summary

## Overview
Configarr has been fully implemented as a CronJob that runs hourly to automatically configure Sonarr, Radarr, and Prowlarr with TRaSH Guides recommendations.

## Components Implemented

### 1. CronJob (`charts/media-server/templates/configarr/cronjob.yaml`)
- **Schedule**: Runs every hour (`0 * * * *`)
- **Image**: `ghcr.io/raydak-labs/configarr:latest`
- **Resource Limits**: 512Mi memory, 200m CPU
- **Persistent Storage**: Host path for repository caching at `/data/config/configarr/repos`
- **Environment Variables**: 
  - Service URLs for Sonarr, Radarr, Prowlarr
  - API keys from External Secrets (optional, graceful handling)
  - LOG_LEVEL and DRY_RUN configuration

### 2. ConfigMap (`charts/media-server/templates/configarr/configmap.yaml`)
- **TRaSH Guides Integration**: Pulls from official TRaSH Guides repository
- **Recyclarr Templates**: Uses official config templates
- **Comprehensive Sonarr Configuration**:
  - WEB-1080p and WEB-2160p quality profiles
  - HDR/DV custom formats with scoring (1500 points)
  - HDR10+ formats (600 points)
  - Standard HDR formats (500 points)
  - Audio quality formats (250 points)
  - Language preferences (VOSTFR: 1000, Original+French: 500)
  - Negative scoring for unwanted formats (-10000 points)
- **Complete Radarr Configuration**:
  - Movie-specific quality profiles
  - Same HDR/DV scoring as Sonarr
  - Additional audio formats (TrueHD Atmos, DTS-X, etc.)
  - Same language and quality preferences
- **Prowlarr Integration**: Base URL and API key configuration

### 3. External Secret (`charts/media-server/templates/configarr/secret.yaml`)
- **Infisical Integration**: Pulls API keys from Infisical secret store
- **Template Generation**: Creates `secrets.yml` file for Configarr
- **API Keys**: Sonarr, Radarr, and Prowlarr API keys
- **Graceful Handling**: Optional keys that don't break if missing

## Configuration Features

### Quality Profiles
- **WEB-1080p**: Optimized for 1080p web releases
- **WEB-2160p**: Optimized for 4K web releases
- **HDR Support**: Full HDR, HDR10+, Dolby Vision support
- **Audio Quality**: Prioritizes lossless and high-quality audio

### Custom Formats Scoring
- **Dolby Vision**: 1500 points (highest priority)
- **HDR10+**: 600 points
- **Standard HDR**: 500 points
- **High-Quality Audio**: 250 points
- **Language Preferences**: VOSTFR (1000), Original+French (500)
- **Unwanted Formats**: -10000 points (BR-DISK, LQ, x265 HD, 3D, etc.)

### Language Handling
- **Preferred**: VOSTFR (French subtitles)
- **Acceptable**: Original + French audio
- **Rejected**: Non-original language content

## Deployment Integration

### Helm Values
```yaml
configarr:
  enabled: true
  image: ghcr.io/raydak-labs/configarr:latest
  schedule: "0 * * * *"
  resources:
    requests:
      memory: "128Mi"
      cpu: "50m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

### External Dependencies
- **Infisical**: For API key management
- **External Secrets Operator**: For secret synchronization
- **Host Path Storage**: For repository caching

## Operational Benefits

1. **Automated Configuration**: No manual setup of quality profiles
2. **Consistent Standards**: TRaSH Guides best practices applied automatically
3. **Regular Updates**: Hourly sync keeps configurations current
4. **Graceful Degradation**: Works even if API keys are missing initially
5. **Resource Efficient**: Minimal resource usage, runs only when needed
6. **Persistent Caching**: Repository cache reduces download time

## Usage

1. **Initial Deployment**: Configarr will attempt to configure services
2. **API Key Updates**: Update API keys in Infisical after services are running
3. **Automatic Sync**: Configurations update hourly automatically
4. **Manual Trigger**: Can be triggered manually via Kubernetes CronJob

## Monitoring

- **Job History**: Keeps 1 successful and 1 failed job for troubleshooting
- **Logs**: Available via `kubectl logs` for debugging
- **Status**: CronJob status shows last execution results

This implementation provides a fully automated, production-ready configuration management system for the media server stack.