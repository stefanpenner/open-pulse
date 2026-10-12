# Open Pulse scripts

## `install-device.sh`

Build Debug + install to a **paired** physical iPhone.

```bash
# Stefan's iPhone (default when available)
./scripts/install-device.sh
./scripts/install-device.sh stefan

# Other paired device named "iPhone"
./scripts/install-device.sh other
```

**Requirements**
- Phone unlocked (or install succeeds, launch waits for unlock)
- Trusted this Mac
- Valid Apple Development cert + team `T93925EZUT`
- Deployment target iOS 26+

**Env overrides**
- `OPENPULSE_DERIVED` — DerivedData path (default `/tmp/OpenPulse-device-build`)
- `OPENPULSE_DEVICE` — coredevice UUID
