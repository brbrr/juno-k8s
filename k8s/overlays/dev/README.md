# Development Overlays

These PVCs have reduced storage sizes for testing with limited disk space.

## Storage Sizes

- **Juno**: 50Gi (vs 400Gi production)
- **Prometheus**: 2Gi (vs 20Gi production)
- **Loki**: 2Gi (vs 20Gi production)
- **Grafana**: 1Gi (vs 2Gi production)

**Total**: ~55Gi (vs 442Gi production)

## Usage

Deploy with dev configuration:
```bash
./scripts/apply-dev.sh
```

## Notes

- Juno won't fully sync with only 50Gi but will work for testing
- Prometheus and Loki have shorter retention
- All functionality will work, just with limited storage
