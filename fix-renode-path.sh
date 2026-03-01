#!/bin/bash
# Quick fix script to update Renode PATH configuration

sudo tee /etc/profile.d/dmboot-tools.sh >/dev/null << 'EOF'
#!/usr/bin/env sh
# DMOD Boot tools PATH configuration
if [ -d "/tools/renode_1.15.3_portable" ]; then
    case ":$PATH:" in
        *:"/tools/renode_1.15.3_portable":*) ;;
        *) export PATH="$PATH:/tools/renode_1.15.3_portable" ;;
    esac
fi
EOF

sudo chmod 644 /etc/profile.d/dmboot-tools.sh
echo "✓ Zaktualizowano /etc/profile.d/dmboot-tools.sh"
echo "Uruchom: source /etc/profile.d/dmboot-tools.sh"
echo "Lub otwórz nowy terminal"
